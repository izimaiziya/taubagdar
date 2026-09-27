import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../alan/suggestions.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/iter.dart';
import '../../data/stores.dart';
import '../../data/hike.dart';
import '../../data/trip_package.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';
import '../shell/main_shell.dart';

class AlanHome extends ConsumerWidget {
  const AlanHome({super.key});

  String _greeting(int h) => h < 5
      ? 'Доброй ночи'
      : h < 12
          ? 'Доброе утро'
          : h < 18
              ? 'Добрый день'
              : 'Добрый вечер';

  void _act(BuildContext context, WidgetRef ref, AlanSuggestion s) {
    switch (s.action) {
      case SuggestionAction.openChat:
        context.push('/chat', extra: s.payload);
      case SuggestionAction.openTrip:
        context.push('/trip/${s.payload}');
      case SuggestionAction.openContacts:
        ref.read(tabProvider.notifier).select(4);
      case SuggestionAction.openRoutes:
        ref.read(tabProvider.notifier).select(0);
      case SuggestionAction.openSafety:
        ref.read(tabProvider.notifier).select(3);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final mood = ref.watch(homeMoodProvider);
    final suggestions = ref.watch(suggestionsProvider);
    final trip = ref.watch(nextTripProvider);
    final now = almatyNow();
    final t = Theme.of(context).textTheme;

    final line = trip != null
        ? (() {
            final d = trip.date.difference(almatyToday()).inDays;
            return d == 0
                ? 'Сегодня идём на ${trip.routeName}.'
                : d == 1
                    ? 'Завтра идём на ${trip.routeName}.'
                    : 'До похода на ${trip.routeName} $d дн.';
          })()
        : 'Куда пойдём в эти выходные?';

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Container(
          color: Tb.air,
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const TbLogo(height: 44),
                      const SizedBox(height: 12),
                      Text('${_greeting(now.hour)},\n${p.name.isEmpty ? 'турист' : p.name}!', style: t.displaySmall),
                      const SizedBox(height: 8),
                      Text(line, style: t.bodyLarge?.copyWith(color: Tb.ink)),
                    ]),
                  ),
                  AlanFigure(mood: mood, height: 150, breathe: true),
                ]),
              ),
              const SizedBox(height: 8),
              const Ridges(seed: 2026, height: 64, sky: Tb.air, front: Tb.ice, snowCaps: true),
            ]),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        sliver: SliverList.list(children: [
          const _NextTrip(),
          if (suggestions.isNotEmpty) const SectionTitle('Алан советует'),
          for (var i = 0; i < suggestions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SuggestionCard(suggestions[i], onTap: () => _act(context, ref, suggestions[i]))
                  .animate(delay: (80 * i).ms)
                  .fadeIn(duration: 260.ms),
            ),
          const SectionTitle('Спросить Алана'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in const [
              'Куда пойти в субботу?',
              'Какая погода в горах на выходных?',
              'Что взять на Кок-Жайляу?',
              'Что делать, если заблудился?',
            ])
              ActionChip(
                label: Text(q),
                onPressed: () => context.push('/chat', extra: q),
                backgroundColor: Tb.snow,
                side: const BorderSide(color: Tb.mist, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                labelStyle: const TextStyle(fontFamily: Tb.body, fontSize: 14.5, fontWeight: FontWeight.w500, color: Tb.night),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.push('/chat'),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Tb.snow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Tb.mist, width: 1.5),
              ),
              child: Row(children: [
                Expanded(child: Text('Напиши Алану…', style: t.bodyLarge?.copyWith(color: Tb.slate))),
                const Icon(Icons.arrow_upward_rounded, color: Tb.sky),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Главное на сегодня: идущий поход, ближайший поход или приглашение выбрать маршрут.
class _NextTrip extends ConsumerWidget {
  const _NextTrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final hike = ref.watch(hikeProvider);
    final trip = ref.watch(nextTripProvider);

    if (hike != null) {
      final active = ref.watch(tripsProvider).where((x) => x.id == hike.tripId).firstOrNone;
      return Material(
        color: Tb.night,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => context.push('/hike/${hike.tripId}'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Icon(Icons.hiking_rounded, color: Colors.white, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Поход идёт', style: t.titleLarge?.copyWith(color: Colors.white)),
                  Text('${active?.routeName ?? ''} · контрольное время ${hhmm(hike.controlAt)}',
                      style: t.bodyMedium?.copyWith(color: Colors.white70)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),
      );
    }

    if (trip != null) {
      final days = trip.date.difference(almatyToday()).inDays;
      return Material(
        color: Tb.snow,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => context.push('/trip/${trip.id}'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              ReadinessRing(ref.watch(readinessProvider(trip.id)), size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(days == 0 ? 'Сегодня' : days == 1 ? 'Завтра' : DateFormat('EEEE, d MMMM', 'ru').format(trip.date),
                      style: t.labelMedium?.copyWith(color: Tb.skyDeep)),
                  Text(trip.routeName, style: t.headlineSmall),
                  Text('Разворот до ${hhmm(trip.turnaround)}', style: t.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Tb.slate),
            ]),
          ),
        ),
      );
    }

    return Sheet(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Поход ещё не запланирован', style: t.titleLarge),
        const SizedBox(height: 6),
        Text('Выбери маршрут и день в календаре — я посчитаю время разворота и соберу рюкзак.', style: t.bodyMedium),
        const SizedBox(height: 14),
        TbButton('Выбрать маршрут', icon: Icons.terrain_rounded, onPressed: () => ref.read(tabProvider.notifier).select(0)),
      ]),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(this.s, {required this.onTap});
  final AlanSuggestion s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = s.priority >= 85;
    final t = Theme.of(context).textTheme;
    return Material(
      color: urgent ? Tb.night : Tb.snow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: urgent ? Tb.sky : Tb.air,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(s.icon, color: urgent ? Colors.white : Tb.sky, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: t.titleMedium?.copyWith(color: urgent ? Colors.white : Tb.night)),
                const SizedBox(height: 4),
                Text(s.body, style: t.bodyMedium?.copyWith(color: urgent ? Colors.white.withValues(alpha: .85) : Tb.ink)),
                const SizedBox(height: 8),
                Text(s.cta,
                    style: TextStyle(
                        fontFamily: Tb.body, fontWeight: FontWeight.w700, fontSize: 15, color: urgent ? Tb.haze : Tb.sky)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
