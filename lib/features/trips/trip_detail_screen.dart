import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../alan/alan_mood.dart';
import '../../alan/planner.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/iter.dart';
import '../../data/hike.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../data/trip_package.dart';
import '../../data/weather_service.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';
import '../shell/main_shell.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});
  final String tripId;
  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    ref.read(profileProvider.notifier).refreshLinks();
  }

  /// Прогноз для экрана: из пакета, иначе последний сохранённый.
  WeatherReport? _forecast(RouteInfo route, TripPackage? pkg) => pkg != null
      ? ref.read(packagesProvider.notifier).forecastFrom(pkg, route)
      : ref.read(weatherServiceProvider).savedFor(route);

  Future<void> _download(Trip trip, RouteInfo route) async {
    setState(() => _downloading = true);
    try {
      final pkg = await ref.read(packagesProvider.notifier).download(trip);
      // План пересчитываем по свежему прогнозу, чтобы в походе были точные времена.
      final day = ref.read(packagesProvider.notifier).forecastFrom(pkg, route)?.day(trip.date);
      if (day != null) {
        ref.read(tripsProvider.notifier).updatePlan(trip.id, Planner(ref.read(profileProvider)).dayPlan(route, day));
      }
      _toast('Пакет скачан. Теперь поход работает без связи.');
    } on WeatherError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Не получилось скачать. Проверьте интернет.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _start(Trip trip, List<PackageCheck> checks) async {
    final failed = checks.where((c) => !c.ok).toList();
    if (failed.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Не всё готово'),
          content: Text(failed.map((f) => '• ${f.title}: ${f.detail}').join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Исправить')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Всё равно начать')),
          ],
        ),
      );
      if (go != true) return;
    }
    await ref.read(hikeProvider.notifier).start(trip);
    if (mounted) context.push('/hike/${trip.id}');
  }

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripsProvider).where((x) => x.id == widget.tripId).firstOrNone;
    if (trip == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Поход не найден')));

    final t = Theme.of(context).textTheme;
    final route = (ref.watch(routesProvider).value ?? const <RouteInfo>[]).where((r) => r.id == trip.routeId).firstOrNone;
    final profile = ref.watch(profileProvider);
    final pkg = ref.watch(packagesProvider)[trip.id];
    final hike = ref.watch(hikeProvider);
    final readiness = ref.watch(readinessProvider(trip.id));
    final checks = ref.read(packagesProvider.notifier).verify(trip, route, profile);
    final wx = route == null ? null : _forecast(route, pkg);
    final day = wx?.day(trip.date);
    final plan = (route != null && day != null) ? Planner(profile).dayPlan(route, day) : null;
    final active = hike != null && hike.tripId == trip.id;

    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          tooltip: 'Удалить поход',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Удалить поход?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              ref.read(packagesProvider.notifier).remove(trip.id);
              ref.read(tripsProvider.notifier).remove(trip.id);
              context.pop();
            }
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text(DateFormat('EEEE, d MMMM', 'ru').format(trip.date), style: t.labelMedium?.copyWith(color: Tb.skyDeep)),
        const SizedBox(height: 4),
        Text(trip.routeName, style: t.displayMedium),
        const SizedBox(height: 16),

        // 1. Готовность
        ReadinessPanel(readiness),

        // 2. План дня
        const SectionTitle('План дня'),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Tb.night, borderRadius: BorderRadius.circular(26)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Разворот не позднее', style: t.bodySmall?.copyWith(color: Colors.white70)),
            Text(hhmm(trip.turnaround),
                style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 40, color: Colors.white)),
            if (plan != null) Text('Ограничение: ${plan.limitingFactor}', style: t.bodySmall?.copyWith(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),
        Sheet(
          child: Column(children: [
            for (final i in plan?.timeline ??
                [
                  TimelineItem(trip.start, 'Старт на тропе'),
                  TimelineItem(trip.turnaround, 'Разворот не позднее', key: true),
                  TimelineItem(trip.returnBy, 'Возвращение к старту'),
                ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 56,
                    child: Text(hhmm(i.time),
                        style: TextStyle(
                            fontFamily: Tb.display, fontWeight: FontWeight.w700, fontSize: 15, color: i.key ? Tb.sky : Tb.night)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.title, style: t.titleMedium?.copyWith(fontSize: 15)),
                      if (i.note != null) Text(i.note!, style: t.bodySmall),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),

        // 3. Погода на трёх высотах
        const SectionTitle('Погода на маршруте'),
        if (wx == null || day == null)
          Sheet(
            child: Text(
              trip.date.difference(almatyToday()).inDays > 14
                  ? 'Прогноз на эту дату появится примерно за две недели. Скачайте пакет накануне похода.'
                  : 'Прогноза пока нет. Скачайте пакет похода.',
              style: t.bodyMedium,
            ),
          )
        else
          Sheet(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${weatherText(day.code)}, ${tempText(day.tMax)} / ${tempText(day.tMin)}', style: t.titleMedium)),
                Pill(verdictText(day.verdict), color: verdictColor(day.verdict)),
              ]),
              const SizedBox(height: 10),
              LevelsTable(report: wx, date: trip.date),
              const SizedBox(height: 8),
              for (final w in day.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Tb.caution),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w, style: t.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 6),
              Text(levelsCaption(wx), style: t.bodySmall),
            ]),
          ),

        // 4. Пакет похода
        const SectionTitle('Пакет для работы без связи'),
        Sheet(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Прогноз на трёх высотах, план и контакты сохраняются на телефоне. Инструкции первой помощи уже внутри.',
                style: t.bodyMedium),
            const SizedBox(height: 12),
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(c.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 20, color: c.ok ? Tb.safe : Tb.caution),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${c.title}: ', style: t.titleMedium?.copyWith(fontSize: 15)),
                      TextSpan(text: c.detail, style: t.bodyMedium),
                    ])),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            TbButton(
              _downloading ? 'Скачиваю…' : (pkg == null ? 'Скачать пакет' : 'Обновить пакет'),
              icon: Icons.download_rounded,
              onPressed: _downloading || route == null ? null : () => _download(trip, route),
            ),
          ]),
        ),

        // 5. Рюкзак
        const SectionTitle('Рюкзак'),
        Sheet(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('Собрано ${trip.packed.length} из ${trip.checklist.length}', style: t.titleMedium),
              subtitle: Text(trip.criticalLeft == 0 ? 'Всё важное на месте' : 'Важных осталось: ${trip.criticalLeft}',
                  style: t.bodySmall),
              children: [
                for (final i in trip.checklist)
                  CheckboxListTile(
                    value: trip.packed.contains(i.id),
                    onChanged: (_) {
                      HapticFeedback.selectionClick();
                      ref.read(tripsProvider.notifier).togglePacked(trip.id, i.id);
                    },
                    activeColor: Tb.sky,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(children: [
                      Flexible(child: Text(i.title, style: t.titleMedium?.copyWith(fontSize: 15))),
                      if (i.critical) ...[const SizedBox(width: 6), const Pill('важно', color: Tb.sky)],
                    ]),
                    subtitle: Text(i.owned ? i.why : '${i.why} Нужно купить или взять напрокат.', style: t.bodySmall),
                  ),
              ],
            ),
          ),
        ),

        // 6. Контакты и ДЧС
        const SectionTitle('Кто узнает, если вы не вернётесь'),
        Sheet(
          child: profile.contacts.isEmpty
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const AlanSays('Никто. Добавь близкого человека — без этого я не смогу позвать помощь.',
                      mood: MascotMood.worried, avatar: 48),
                  const SizedBox(height: 12),
                  TbButton('Добавить контакт', onPressed: () {
                    ref.read(tabProvider.notifier).select(4);
                    context.go('/app');
                  }),
                ])
              : Column(children: [
                  for (final c in profile.contacts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                          backgroundColor: Tb.air,
                          child: Text(c.name.isEmpty ? '?' : c.name[0], style: const TextStyle(color: Tb.skyDeep))),
                      title: Text(c.name, style: t.titleMedium),
                      subtitle: Text(
                          c.verified
                              ? 'Подключён к Telegram-боту — получит тревогу'
                              : (Env.hasSupabase ? 'Ещё не открыл приглашение в Telegram' : 'Сервер тревоги не подключён'),
                          style: t.bodySmall),
                      trailing: Icon(c.verified ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
                          color: c.verified ? Tb.safe : Tb.slate),
                    ),
                ]),
        ),
        const SizedBox(height: 12),
        Sheet(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(trip.dchsNotified ? 'ДЧС уведомлён' : 'Уведомить ДЧС', style: t.titleMedium),
              subtitle: Text('Обязательно для туристов: eQonaq, email ДЧС или 112', style: t.bodySmall),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Tb.ice, borderRadius: BorderRadius.circular(16)),
                  child: SelectableText(dchsNotificationText(profile, trip, route), style: t.bodyMedium),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: dchsNotificationText(profile, trip, route)));
                      _toast('Текст скопирован');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Скопировать'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:112')),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Позвонить 112'),
                  ),
                ]),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: trip.dchsNotified,
                  activeTrackColor: Tb.sky,
                  onChanged: (v) => ref.read(tripsProvider.notifier).setNotified(trip.id, v),
                  title: Text('Я уведомил ДЧС', style: t.titleMedium),
                ),
              ],
            ),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: active
              ? TbButton('Открыть поход', icon: Icons.hiking_rounded, onPressed: () => context.push('/hike/${trip.id}'))
              : TbButton(
                  'Начать поход',
                  icon: Icons.play_arrow_rounded,
                  color: checks.every((c) => c.ok) ? Tb.sky : Tb.skyDeep,
                  onPressed: hike != null ? null : () => _start(trip, checks),
                ),
        ),
      ),
    );
  }
}
