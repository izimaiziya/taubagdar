import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../alan/safety_content.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
        Text('Помощь', style: t.displayMedium),
        const SizedBox(height: 6),
        Text('Работает без интернета', style: t.bodyLarge?.copyWith(color: Tb.slate)),
        const SizedBox(height: 20),
        const _SosHold(),
        const SectionTitle('Если что-то случилось'),
        for (final topic in safetyTopics)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Tb.snow,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  title: Text(topic.title, style: t.titleMedium),
                  subtitle: Text(topic.lead, style: t.bodySmall),
                  iconColor: Tb.sky,
                  collapsedIconColor: Tb.slate,
                  children: [
                    for (var i = 0; i < topic.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 26,
                            child: Text('${i + 1}',
                                style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, color: Tb.sky, fontSize: 16)),
                          ),
                          Expanded(child: Text(topic.steps[i], style: t.bodyLarge)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('Инструкции не заменяют обучение первой помощи и звонок в 112.', style: t.bodySmall),
      ]),
    );
  }
}

/// SOS срабатывает после удержания 1,5 секунды — защита от случайного нажатия.
class _SosHold extends StatefulWidget {
  const _SosHold();
  @override
  State<_SosHold> createState() => _SosHoldState();
}

class _SosHoldState extends State<_SosHold> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _c.reset();
        context.push('/sos');
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        _c.forward();
      },
      onPointerUp: (_) => _c.reverse(),
      onPointerCancel: (_) => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          height: 132,
          decoration: BoxDecoration(color: Tb.danger, borderRadius: BorderRadius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            FractionallySizedBox(
              widthFactor: _c.value,
              child: Container(color: Colors.black.withValues(alpha: .18)),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(children: [
                const Icon(Icons.sos_rounded, color: Colors.white, size: 52),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Мне нужна помощь',
                        style: TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(_c.value > 0 ? 'Держи…' : 'Удерживай, чтобы открыть экран SOS',
                        style: const TextStyle(fontFamily: Tb.body, fontSize: 15, color: Colors.white)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
