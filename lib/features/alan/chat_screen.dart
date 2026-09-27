import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../alan/alan_brain.dart';
import '../../alan/alan_mood.dart';
import '../../alan/planner.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../data/weather_service.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.initialPrompt});
  final String? initialPrompt;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final q = widget.initialPrompt;
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(q));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    _input.clear();
    final f = ref.read(chatProvider.notifier).send(text);
    _toBottom();
    await f;
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          AlanAvatar(mood: chat.thinking ? MascotMood.thinking : MascotMood.happy, size: 40),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Алан', style: Theme.of(context).textTheme.titleLarge),
            Text(chat.thinking ? 'думает…' : (Env.hasAi ? 'на связи' : 'отвечает без ИИ'),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: chat.messages.length + (chat.thinking ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == chat.messages.length) return const _Typing();
              final m = chat.messages[i];
              return m.fromAlan ? _AlanMessage(m) : _UserMessage(m.text);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(hintText: 'Спроси про маршрут, погоду, вещи…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: chat.thinking ? null : () => _send(_input.text),
                style: IconButton.styleFrom(backgroundColor: Tb.sky, minimumSize: const Size(54, 54)),
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4, left: 60),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Tb.sky,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(text, style: const TextStyle(fontFamily: Tb.body, fontSize: 16.5, color: Colors.white, height: 1.4)),
        ),
      );
}

class _AlanMessage extends StatelessWidget {
  const _AlanMessage(this.m);
  final ChatMessage m;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(right: 40), child: AlanSays(m.text, mood: m.mood, avatar: 46)),
          for (final c in m.cards)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 56),
              child: switch (c) {
                RoutesCard x => _RoutesCardView(x),
                WeatherCard x => _WeatherCardView(x),
                PlanCard x => _PlanCardView(x),
                ChecklistCard x => _ChecklistCardView(x),
                SafetyCard x => _SafetyCardView(x),
              },
            ).animate().fadeIn(duration: 250.ms),
        ]),
      );
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          const AlanAvatar(mood: MascotMood.thinking, size: 46),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: Tb.snow, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(color: Tb.haze, shape: BoxShape.circle),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true), delay: (150 * i).ms)
                    .moveY(begin: 0, end: -4, duration: 400.ms),
            ]),
          ),
        ]),
      );
}

// ─────────────── карточки ───────────────

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.title, required this.child, this.icon, this.trailing});
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tb.snow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Tb.mist, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, color: Tb.sky, size: 20), const SizedBox(width: 8)],
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _RoutesCardView extends StatelessWidget {
  const _RoutesCardView(this.c);
  final RoutesCard c;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final r in c.routes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Tb.snow,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push('/route/${r.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Ridges(seed: r.id.hashCode, height: 64, front: Tb.sky),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.name, style: Theme.of(context).textTheme.titleLarge),
                          Text('${r.difficultyTitle}, ${r.hoursText}', style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Tb.slate),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]);
}

class _WeatherCardView extends StatelessWidget {
  const _WeatherCardView(this.c);
  final WeatherCard c;
  @override
  Widget build(BuildContext context) {
    final d = c.day;
    final t = Theme.of(context).textTheme;
    return _CardFrame(
      title: '${c.route.top?.name ?? c.route.name}, ${DateFormat('d MMMM', 'ru').format(d.date)}',
      icon: weatherIcon(d.code),
      trailing: Pill(verdictText(d.verdict), color: verdictColor(d.verdict)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stat('${tempText(d.tMax)} / ${tempText(d.tMin)}', 'днём / ночью'),
          const SizedBox(width: 24),
          Stat('${d.gustMax.round()} км/ч', 'порывы'),
          const SizedBox(width: 24),
          Stat(hhmm(d.sunset), 'закат'),
        ]),
        if (c.report != null) ...[
          const SizedBox(height: 14),
          LevelsTable(report: c.report!, date: d.date),
        ],
        for (final w in d.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(d.typical ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                  size: 18, color: d.typical ? Tb.slate : Tb.caution),
              const SizedBox(width: 6),
              Expanded(child: Text(w, style: t.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}

class _PlanCardView extends ConsumerWidget {
  const _PlanCardView(this.c);
  final PlanCard c;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = c.plan;
    final t = Theme.of(context).textTheme;
    final id = '${c.route.id}-${isoDate(p.date)}';
    final saved = ref.watch(tripsProvider).any((x) => x.id == id);
    return _CardFrame(
      title: 'План на ${DateFormat('EEEE, d MMMM', 'ru').format(p.date)}',
      icon: Icons.route_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.feasible ? Tb.night : Tb.danger, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Разворот не позднее', style: t.bodySmall?.copyWith(color: Colors.white70)),
            Text(hhmm(p.turnaround),
                style: const TextStyle(fontFamily: Tb.display, fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('Ограничение: ${p.limitingFactor}', style: t.bodySmall?.copyWith(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),
        for (final item in p.timeline)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 54,
                child: Text(hhmm(item.time),
                    style: TextStyle(
                        fontFamily: Tb.display,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: item.key ? Tb.sky : Tb.night)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, style: t.titleMedium?.copyWith(fontSize: 15)),
                  if (item.note != null) Text(item.note!, style: t.bodySmall),
                ]),
              ),
            ]),
          ),
        for (final n in p.notes)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(n, style: t.bodySmall)),
        const SizedBox(height: 14),
        TbButton(
          saved ? 'Поход сохранён' : 'Сохранить поход',
          icon: saved ? Icons.check_rounded : Icons.bookmark_add_rounded,
          onPressed: saved
              ? () => context.push('/trip/$id')
              : () {
                  final items = Planner(ref.read(profileProvider)).checklist(c.route, c.day);
                  ref.read(tripsProvider.notifier).add(Trip(
                        id: id,
                        routeId: c.route.id,
                        routeName: c.route.name,
                        date: p.date,
                        start: p.start,
                        turnaround: p.turnaround,
                        returnBy: p.returnBy,
                        checklist: items,
                      ));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Поход сохранён. Список вещей — в разделе «Походы».')));
                },
        ),
      ]),
    );
  }
}

class _ChecklistCardView extends StatelessWidget {
  const _ChecklistCardView(this.c);
  final ChecklistCard c;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final groups = <String, List<ChecklistItem>>{};
    for (final i in c.items) {
      groups.putIfAbsent(i.group, () => []).add(i);
    }
    return _CardFrame(
      title: 'Что взять на ${c.route.name}',
      icon: Icons.backpack_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final g in groups.entries) ...[
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(g.key, style: t.labelMedium)),
          for (final i in g.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i.critical ? Icons.priority_high_rounded : Icons.circle, size: i.critical ? 18 : 7, color: i.critical ? Tb.sky : Tb.haze),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.title, style: t.titleMedium?.copyWith(fontSize: 15)),
                    Text(i.owned ? i.why : '${i.why} Нужно купить или взять напрокат.', style: t.bodySmall),
                  ]),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _SafetyCardView extends StatelessWidget {
  const _SafetyCardView(this.c);
  final SafetyCard c;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _CardFrame(
      title: c.topic.title,
      icon: Icons.health_and_safety_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.topic.lead, style: t.bodyMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < c.topic.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 24,
                child: Text('${i + 1}', style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, color: Tb.sky)),
              ),
              Expanded(child: Text(c.topic.steps[i], style: t.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}
