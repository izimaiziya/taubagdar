import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alan/planner.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../ui/widgets.dart';

class _OnlyMine extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final _onlyMineProvider = NotifierProvider<_OnlyMine, bool>(_OnlyMine.new);

class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    final onlyMine = ref.watch(_onlyMineProvider);
    final planner = Planner(ref.watch(profileProvider));
    final t = Theme.of(context).textTheme;

    return SafeArea(
      bottom: false,
      child: routes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          final list = onlyMine ? all.where((r) => planner.whyNot(r) == null).toList() : all;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
            Text('Маршруты', style: t.displayMedium),
            const SizedBox(height: 6),
            Text('Заилийский Алатау над Алматы', style: t.bodyLarge?.copyWith(color: Tb.slate)),
            const SizedBox(height: 16),
            Row(children: [
              FilterChip(
                label: const Text('Мне по силам'),
                selected: onlyMine,
                onSelected: (v) => ref.read(_onlyMineProvider.notifier).set(v),
                selectedColor: Tb.sky,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                    fontFamily: Tb.body, fontWeight: FontWeight.w600, color: onlyMine ? Colors.white : Tb.night),
                backgroundColor: Tb.snow,
                side: BorderSide(color: onlyMine ? Tb.sky : Tb.mist, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
            ]),
            const SizedBox(height: 16),
            if (list.isEmpty)
              const AlanSays('Пока нет маршрутов под твой уровень. Скоро добавлю новые.', avatar: 60),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: RouteTile(route: r, fitReason: planner.whyNot(r)),
              ),
          ]);
        },
      ),
    );
  }
}

class RouteTile extends StatelessWidget {
  const RouteTile({super.key, required this.route, this.fitReason});
  final RouteInfo route;
  final String? fitReason;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = route;
    return Material(
      color: Tb.snow,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/route/${r.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Ridges(seed: r.id.hashCode, height: 132, front: r.verified ? Tb.sky : Tb.haze),
            Positioned(
              left: 14,
              top: 14,
              child: Pill(r.difficultyTitle, color: difficultyColor(r.difficulty), filled: true),
            ),
            if (!r.verified)
              const Positioned(right: 14, top: 14, child: Pill('Данные проверяются', color: Tb.slate, filled: true)),
            if (r.maxEleM != null)
              Positioned(
                right: 16,
                bottom: 12,
                child: Text('${r.maxEleM} м',
                    style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: t.headlineSmall),
              const SizedBox(height: 4),
              Text(r.subtitle, style: t.bodyMedium?.copyWith(color: Tb.slate)),
              const SizedBox(height: 12),
              Row(children: [
                Stat(r.hoursText, 'туда и обратно', icon: Icons.schedule_rounded),
                const SizedBox(width: 22),
                if (r.lengthKm != null) Stat('${r.lengthKm!.toStringAsFixed(0)} км', 'протяжённость', icon: Icons.straighten_rounded),
              ]),
              if (fitReason != null && r.verified) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: Tb.caution),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Пока не для тебя: $fitReason', style: t.bodySmall?.copyWith(color: Tb.ink))),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
