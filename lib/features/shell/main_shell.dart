import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alan/suggestions.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../alan/alan_home.dart';
import '../profile/profile_screen.dart';
import '../routes/routes_screen.dart';
import '../safety/safety_screen.dart';
import '../trips/trips_screen.dart';

/// Переключение вкладки из любого места (например, из подсказки Алана).
class TabNotifier extends Notifier<int> {
  @override
  int build() => 2; // по умолчанию открыт Алан

  void select(int i) => state = i;
}

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _pages = [RoutesScreen(), TripsScreen(), AlanHome(), SafetyScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(index: tab, children: _pages),
      bottomNavigationBar: _BottomBar(
        index: tab,
        onTap: (i) {
          HapticFeedback.selectionClick();
          ref.read(tabProvider.notifier).select(i);
        },
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(homeMoodProvider);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Tb.snow,
        boxShadow: [BoxShadow(color: Tb.night.withValues(alpha: .06), blurRadius: 24, offset: const Offset(0, -6))],
      ),
      padding: EdgeInsets.only(bottom: bottom > 0 ? bottom - 6 : 8, top: 6),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          _Item(icon: Icons.terrain_rounded, label: 'Маршруты', active: index == 0, onTap: () => onTap(0)),
          _Item(icon: Icons.event_note_rounded, label: 'Походы', active: index == 1, onTap: () => onTap(1)),
          Expanded(
            child: GestureDetector(
              onTap: () => onTap(2),
              behavior: HitTestBehavior.opaque,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Transform.translate(
                  offset: const Offset(0, -14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 68,
                    height: 68,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: index == 2 ? Tb.air : Tb.snow,
                      shape: BoxShape.circle,
                      border: Border.all(color: index == 2 ? Tb.night : Tb.mist, width: 2.5),
                    ),
                    child: AlanAvatar(mood: mood, size: 50),
                  ),
                ),
              ]),
            ),
          ),
          _Item(icon: Icons.health_and_safety_rounded, label: 'Помощь', active: index == 3, onTap: () => onTap(3)),
          _Item(icon: Icons.person_rounded, label: 'Профиль', active: index == 4, onTap: () => onTap(4)),
        ]),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkResponse(
          onTap: onTap,
          radius: 36,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: active ? Tb.sky : Tb.slate.withValues(alpha: .75), size: 26),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontFamily: Tb.body,
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Tb.sky : Tb.slate)),
          ]),
        ),
      );
}
