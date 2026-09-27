import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../alan/alan_mood.dart';
import '../../alan/planner.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../data/weather_service.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key, required this.routeId});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    return Scaffold(
      body: routes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          final r = all.firstWhere((x) => x.id == routeId);
          return _Body(r);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.r);
  final RouteInfo r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final why = Planner(ref.watch(profileProvider)).whyNot(r);
    final top = MediaQuery.of(context).padding.top;

    return Stack(children: [
      ListView(padding: EdgeInsets.zero, children: [
        Container(
          color: Tb.air,
          padding: EdgeInsets.only(top: top + 56),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Pill(r.difficultyTitle, color: difficultyColor(r.difficulty), filled: true),
                const SizedBox(height: 12),
                Text(r.name, style: t.displayMedium),
                const SizedBox(height: 6),
                Text(r.subtitle, style: t.bodyLarge?.copyWith(color: Tb.ink)),
              ]),
            ),
            const SizedBox(height: 10),
            Ridges(seed: r.id.hashCode, height: 110, front: Tb.ice),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Sheet(
              child: Wrap(spacing: 26, runSpacing: 14, children: [
                Stat(r.hoursText, 'туда и обратно', icon: Icons.schedule_rounded),
                if (r.maxEleM != null) Stat('${r.maxEleM} м', 'высшая точка', icon: Icons.landscape_rounded),
                if (r.lengthKm != null) Stat('${r.lengthKm!.toStringAsFixed(0)} км', 'протяжённость', icon: Icons.straighten_rounded),
              ]),
            ),
            const SizedBox(height: 18),
            AlanSays(
              !r.verified
                  ? 'Этот маршрут я ещё проверяю: у меня нет точного трека. Пока не могу его планировать.'
                  : why == null
                      ? 'Этот маршрут тебе по силам. Выходи пораньше — так останется запас до заката.'
                      : 'Пока рановато: $why. Давай начнём с чего-то попроще.',
              mood: !r.verified ? MascotMood.thinking : (why == null ? MascotMood.happy : MascotMood.worried),
              avatar: 60,
            ),
            if (r.points.isNotEmpty) ...[
              const SectionTitle('Карта'),
              _RouteMap(r),
              const SizedBox(height: 8),
              Text('Показаны ключевые точки из описания маршрута, а не GPS-трек.', style: t.bodySmall),
            ],
            if (r.plannable) ...[
              const SectionTitle('Погода и план'),
              _RouteWeather(r),
            ],
            const SectionTitle('Как добраться'),
            Text(r.howToGet, style: t.bodyLarge),
            if (r.risks.isNotEmpty) ...[
              const SectionTitle('На что обратить внимание'),
              for (final s in r.risks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.warning_amber_rounded, color: Tb.caution, size: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s, style: t.bodyLarge)),
                  ]),
                ),
            ],
            if (r.feeNote.isNotEmpty) ...[
              const SectionTitle('Вход в нацпарк'),
              Text(r.feeNote, style: t.bodyLarge),
            ],
            const SectionTitle('Источники'),
            for (final s in r.sources)
              InkWell(
                onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.link_rounded, size: 18, color: Tb.sky),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.title, style: t.bodyMedium?.copyWith(color: Tb.skyDeep))),
                  ]),
                ),
              ),
            if (r.accessVerifiedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Доступ проверен: ${r.accessVerifiedAt}', style: t.bodySmall),
              ),
          ]),
        ),
      ]),
      Positioned(
        top: top + 6,
        left: 8,
        child: IconButton.filledTonal(
          onPressed: () => context.pop(),
          style: IconButton.styleFrom(backgroundColor: Tb.snow),
          icon: const Icon(Icons.arrow_back_rounded, color: Tb.night),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
        child: TbButton(
          'Спросить Алана о маршруте',
          icon: Icons.chat_bubble_rounded,
          onPressed: () => context.push('/chat',
              extra: 'Расскажи про маршрут ${r.name}: что важно знать и когда лучше идти?'),
        ),
      ),
    ]);
  }
}

class _RouteMap extends StatelessWidget {
  const _RouteMap(this.r);
  final RouteInfo r;

  @override
  Widget build(BuildContext context) {
    final pts = r.points.map((p) => LatLng(p.lat, p.lon)).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: pts.first,
            initialZoom: 13,
            initialCameraFit: pts.length >= 2
                ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(40))
                : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            // Для хакатона — стандартные тайлы OSM с указанием приложения.
            // Для релиза: офлайн-пакет карты (PMTiles/MBTiles), см. README.
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.taubagdar.app',
            ),
            MarkerLayer(markers: [
              for (final p in r.points)
                Marker(
                  point: LatLng(p.lat, p.lon),
                  width: 36,
                  height: 36,
                  child: Tooltip(
                    message: p.name,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.role == 'top' ? Tb.night : (p.role == 'start' ? Tb.sky : Tb.snow),
                        shape: BoxShape.circle,
                        border: Border.all(color: p.role == 'waypoint' ? Tb.sky : Colors.white, width: 3),
                      ),
                      child: Icon(
                        p.role == 'top' ? Icons.flag_rounded : (p.role == 'start' ? Icons.hiking_rounded : Icons.place_rounded),
                        size: 17,
                        color: p.role == 'waypoint' ? Tb.sky : Colors.white,
                      ),
                    ),
                  ),
                ),
            ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('участники OpenStreetMap',
                  onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RouteWeather extends ConsumerStatefulWidget {
  const _RouteWeather(this.r);
  final RouteInfo r;
  @override
  ConsumerState<_RouteWeather> createState() => _RouteWeatherState();
}

class _RouteWeatherState extends ConsumerState<_RouteWeather> {
  DateTime? _sel;

  /// Сразу создаём поход с планом и чек-листом и открываем его.
  void _plan(DayWeather day) {
    final profile = ref.read(profileProvider);
    final planner = Planner(profile);
    final p = planner.dayPlan(widget.r, day);
    final id = '${widget.r.id}-${isoDate(day.date)}';
    ref.read(tripsProvider.notifier).add(Trip(
          id: id,
          routeId: widget.r.id,
          routeName: widget.r.name,
          date: day.date,
          start: p.start,
          turnaround: p.turnaround,
          returnBy: p.returnBy,
          checklist: planner.checklist(widget.r, day),
        ));
    context.push('/trip/$id');
  }

  @override
  Widget build(BuildContext context) {
    final wx = ref.watch(forecastProvider(widget.r.id));
    final t = Theme.of(context).textTheme;
    return wx.when(
      loading: () => const LoadingBlock(height: 260),
      error: (e, _) => ErrorNote('$e', onRetry: () => ref.invalidate(forecastProvider(widget.r.id))),
      data: (rep) {
        final sel = _sel ?? rep.days.firstWhere((d) => d.date.weekday >= 6, orElse: () => rep.days.first).date;
        final d = rep.day(sel) ?? rep.days.first;
        final plan = Planner(ref.watch(profileProvider)).dayPlan(widget.r, d);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Sheet(
            padding: const EdgeInsets.all(14),
            child: WeatherCalendar(days: rep.days, selected: sel, onSelect: (x) => setState(() => _sel = x.date)),
          ),
          const SizedBox(height: 12),
          Sheet(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(DateFormat('EEEE, d MMMM', 'ru').format(d.date), style: t.titleLarge),
                ),
                Pill(verdictText(d.verdict), color: verdictColor(d.verdict)),
              ]),
              const SizedBox(height: 10),
              LevelsTable(report: rep, date: d.date),
              for (final w in d.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Tb.caution),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w, style: t.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 22, runSpacing: 10, children: [
                Stat(hhmm(plan.start), 'старт'),
                Stat(hhmm(plan.turnaround), 'разворот'),
                Stat(hhmm(plan.returnBy), 'возвращение'),
                Stat(hhmm(d.sunset), 'закат'),
              ]),
              const SizedBox(height: 8),
              Text(levelsCaption(rep), style: t.bodySmall),
              const SizedBox(height: 14),
              TbButton(
                'Запланировать на ${DateFormat('d MMMM', 'ru').format(d.date)}',
                icon: Icons.event_available_rounded,
                color: d.verdict == DayVerdict.bad ? Tb.slate : Tb.sky,
                onPressed: widget.r.plannable ? () => _plan(d) : null,
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
