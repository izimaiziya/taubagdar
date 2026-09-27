import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../alan/alan_mood.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../data/hike.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../data/trip_package.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider);
    final today = almatyToday();
    final upcoming = trips.where((x) => !x.date.isBefore(today)).toList();
    final past = trips.where((x) => x.date.isBefore(today)).toList().reversed.toList();
    final t = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
        Text('Походы', style: t.displayMedium),
        const SizedBox(height: 20),
        if (ref.watch(hikeProvider) case final h?)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TbButton('Поход идёт — открыть', icon: Icons.hiking_rounded, color: Tb.night,
                onPressed: () => context.push('/hike/${h.tripId}')),
          ),
        if (trips.isEmpty) ...[
          const AlanSays('Здесь появятся твои походы. Давай спланируем первый?', mood: MascotMood.cheering, avatar: 80),
          const SizedBox(height: 20),
          TbButton('Спланировать с Аланом',
              icon: Icons.auto_awesome_rounded,
              onPressed: () => context.push('/chat', extra: 'Подбери мне маршрут на эту субботу')),
        ],
        for (final trip in upcoming)
          Padding(padding: const EdgeInsets.only(bottom: 14), child: _TripCard(trip)),
        if (past.isNotEmpty) ...[
          const SectionTitle('Прошедшие'),
          for (final trip in past)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _TripCard(trip, past: true)),
        ],
      ]),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard(this.trip, {this.past = false});
  final Trip trip;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final days = trip.date.difference(almatyToday()).inDays;
    final when = past
        ? DateFormat('d MMMM', 'ru').format(trip.date)
        : days == 0
            ? 'Сегодня'
            : days == 1
                ? 'Завтра'
                : 'Через $days дн., ${DateFormat('d MMMM', 'ru').format(trip.date)}';

    return Material(
      color: past ? Tb.snow.withValues(alpha: .6) : Tb.snow,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => context.push('/trip/${trip.id}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Consumer(builder: (_, ref, __) => ReadinessRing(ref.watch(readinessProvider(trip.id)), size: 64)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(when, style: t.labelMedium?.copyWith(color: past ? Tb.slate : Tb.skyDeep)),
                const SizedBox(height: 2),
                Text(trip.routeName, style: t.headlineSmall),
                const SizedBox(height: 4),
                Text('Старт ${hhmm(trip.start)}, разворот до ${hhmm(trip.turnaround)}', style: t.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Tb.slate),
          ]),
        ),
      ),
    );
  }
}
