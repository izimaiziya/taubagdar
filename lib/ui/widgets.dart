import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../alan/alan_mood.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../data/weather_service.dart';

// ─────────────────────────── Алан ───────────────────────────
// Рисунки художника: assets/alan/full_*.png. Всегда целиком, без обрезки.

/// Какой рисунок соответствует настроению.
String alanArt(MascotMood m) => switch (m) {
      MascotMood.happy => 'neutral',
      MascotMood.calm => 'map', // «я знаю дорогу»: без связи, в походе, спокойные советы
      MascotMood.cheering => 'delighted',
      MascotMood.thinking => 'questioning', // монокль и карта: думает, задаёт вопросы
      MascotMood.worried || MascotMood.alarmed => 'angry',
    };

/// Небольшой Алан целиком, вписанный в квадрат size × size — для чата, реплик, панели.
class AlanAvatar extends StatelessWidget {
  const AlanAvatar({super.key, this.mood = MascotMood.happy, this.size = 56});
  final MascotMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Image.asset('assets/alan/full_${alanArt(mood)}.png',
              key: ValueKey(alanArt(mood)),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Алан'),
        ),
      );
}

/// Алан в полный рост — для крупных сцен: знакомство, главный экран, регистрация.
class AlanFigure extends StatelessWidget {
  const AlanFigure({super.key, this.mood = MascotMood.happy, this.height = 180, this.breathe = false});
  final MascotMood mood;
  final double height;
  final bool breathe;

  @override
  Widget build(BuildContext context) {
    Widget img = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (c, a) =>
          ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
      child: Image.asset('assets/alan/full_${alanArt(mood)}.png',
          key: ValueKey(alanArt(mood)), height: height, fit: BoxFit.contain, semanticLabel: 'Алан'),
    );
    if (breathe && !MediaQuery.of(context).disableAnimations) {
      img = img
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: 0, end: -height * .02, duration: 1800.ms, curve: Curves.easeInOut);
    }
    return img;
  }
}

/// Логотип «Тау Бағдар», нарисованный от руки.
class TbLogo extends StatelessWidget {
  const TbLogo({super.key, this.height = 48});
  final double height;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/logo.png', height: height, fit: BoxFit.contain, semanticLabel: 'TauBağdar');
}

/// Реплика Алана: аватар + облачко.
class AlanSays extends StatelessWidget {
  const AlanSays(this.text, {super.key, this.mood = MascotMood.happy, this.avatar = 64});
  final String text;
  final MascotMood mood;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      AlanAvatar(mood: mood, size: avatar),
      const SizedBox(width: 10),
      Flexible(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
          decoration: const BoxDecoration(
            color: Tb.snow,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
            ),
          ),
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ).animate(key: ValueKey(text)).fadeIn(duration: 220.ms),
      ),
    ]);
  }
}

// ─────────────────────────── Хребты ───────────────────────────

/// Слои горных хребтов — фирменный мотив TauBağdar.
/// seed задаёт форму, поэтому у каждого маршрута своя «открытка».
class Ridges extends StatelessWidget {
  const Ridges({super.key, this.seed = 7, this.height = 120, this.sky = Tb.air, this.front = Tb.sky, this.snowCaps = true});
  final int seed;
  final double height;
  final Color sky;
  final Color front;
  final bool snowCaps;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _RidgePainter(seed, sky, front, snowCaps)),
      );
}

class _RidgePainter extends CustomPainter {
  _RidgePainter(this.seed, this.sky, this.front, this.snowCaps);
  final int seed;
  final Color sky;
  final Color front;
  final bool snowCaps;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = sky);
    final layers = [
      (Color.lerp(sky, Tb.haze, .55)!, .30, .50, 5),
      (Tb.dusk.withValues(alpha: .75), .48, .40, 4),
      (front, .66, .30, 3),
    ];
    final rnd = math.Random(seed);
    for (var li = 0; li < layers.length; li++) {
      final (color, base, amp, peaks) = layers[li];
      final pts = <Offset>[Offset(0, s.height * (base + rnd.nextDouble() * .1))];
      final step = s.width / (peaks * 2);
      for (var i = 1; i <= peaks * 2; i++) {
        final isPeak = i.isOdd;
        final x = i * step + (rnd.nextDouble() - .5) * step * .5;
        final y = isPeak
            ? s.height * (base - amp * (.45 + rnd.nextDouble() * .55))
            : s.height * (base + rnd.nextDouble() * .12);
        pts.add(Offset(x.clamp(0.0, s.width), y.clamp(4.0, s.height)));
      }
      final path = Path()..moveTo(0, s.height);
      for (final p in pts) {
        path.lineTo(p.dx, p.dy);
      }
      path
        ..lineTo(s.width, pts.last.dy)
        ..lineTo(s.width, s.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
      // Контур хребта тёмно-синей линией — как обводка в рисунках Алана.
      final ridge = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        ridge.lineTo(p.dx, p.dy);
      }
      ridge.lineTo(s.width, pts.last.dy);
      canvas.drawPath(
        ridge,
        Paint()
          ..color = Tb.night.withValues(alpha: li == layers.length - 1 ? .9 : .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = li == layers.length - 1 ? 2.6 : 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      if (snowCaps && li == 1) {
        final snow = Paint()..color = Colors.white.withValues(alpha: .9);
        for (var i = 1; i < pts.length - 1; i++) {
          final p = pts[i];
          if (p.dy < pts[i - 1].dy && p.dy < pts[i + 1].dy) {
            final l = Offset.lerp(p, pts[i - 1], .22)!;
            final r = Offset.lerp(p, pts[i + 1], .22)!;
            final cap = Path()
              ..moveTo(l.dx, l.dy)
              ..lineTo(p.dx, p.dy)
              ..lineTo(r.dx, r.dy)
              ..lineTo((p.dx + r.dx) / 2, r.dy - 3)
              ..lineTo(p.dx, (p.dy + l.dy) / 2 + 4)
              ..close();
            canvas.drawPath(cap, snow);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RidgePainter old) => old.seed != seed || old.front != front || old.sky != sky;
}

// ─────────────────────────── Кнопки ───────────────────────────

class TbButton extends StatelessWidget {
  const TbButton(this.label, {super.key, this.onPressed, this.icon, this.color = Tb.sky, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton(
      onPressed: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: Tb.mist,
        disabledForegroundColor: Tb.slate,
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontFamily: Tb.body, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 21), const SizedBox(width: 10)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class TbTextButton extends StatelessWidget {
  const TbTextButton(this.label, {super.key, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Tb.skyDeep,
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontFamily: Tb.body, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
}

/// Небольшая плашка: сложность, статус.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Tb.sky, this.filled = false, this.icon});
  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: filled ? Colors.white : color), const SizedBox(width: 5)],
          Text(text,
              style: TextStyle(
                  fontFamily: Tb.body, fontSize: 12.5, fontWeight: FontWeight.w600, color: filled ? Colors.white : color)),
        ]),
      );
}

Color difficultyColor(int d) => switch (d) {
      <= 2 => Tb.safe,
      3 => Tb.caution,
      _ => Tb.danger,
    };

/// Значение + подпись.
class Stat extends StatelessWidget {
  const Stat(this.value, this.caption, {super.key, this.icon});
  final String value;
  final String caption;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 17, color: Tb.sky), const SizedBox(width: 5)],
          Text(value,
              style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w700, fontSize: 19, color: Tb.night)),
        ]),
        const SizedBox(height: 2),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Белый блок-лист. Радиус больше, чем у мелких элементов: иерархия видна.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = Tb.snow});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(26)),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.headlineSmall)),
          if (trailing != null) trailing!,
        ]),
      );
}

// ─────────────────────────── Погода ───────────────────────────

Color verdictColor(DayVerdict v) => switch (v) {
      DayVerdict.good => Tb.safe,
      DayVerdict.caution => Tb.caution,
      DayVerdict.bad => Tb.danger,
      DayVerdict.unknown => Tb.slate,
    };

String verdictText(DayVerdict v) => switch (v) {
      DayVerdict.good => 'Хороший день',
      DayVerdict.caution => 'С оговорками',
      DayVerdict.bad => 'Лучше не идти',
      DayVerdict.unknown => 'Примерно',
    };

class WeatherDayTile extends StatelessWidget {
  const WeatherDayTile(this.day, {super.key, this.label, this.selected = false, this.onTap});
  final DayWeather day;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = verdictColor(day.verdict);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Tb.sky : Tb.snow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Tb.sky : Tb.mist, width: 1.5),
        ),
        child: Column(children: [
          Text(label ?? '${day.date.day}',
              style: TextStyle(
                  fontFamily: Tb.body, fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Tb.slate)),
          const SizedBox(height: 8),
          Icon(weatherIcon(day.code), color: selected ? Colors.white : Tb.sky, size: 26),
          const SizedBox(height: 8),
          Text(tempText(day.tMax),
              style: TextStyle(
                  fontFamily: Tb.display, fontSize: 17, fontWeight: FontWeight.w700, color: selected ? Colors.white : Tb.night)),
          Text(tempText(day.tMin),
              style: TextStyle(fontFamily: Tb.body, fontSize: 13, color: selected ? Colors.white70 : Tb.slate)),
          const SizedBox(height: 8),
          Container(width: 22, height: 5, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9))),
        ]),
      ),
    );
  }
}

/// Скелетон на время загрузки.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 120});
  final double height;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: Tb.mist.withValues(alpha: .6), borderRadius: BorderRadius.circular(22)),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: .5, end: 1, duration: 900.ms);
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Sheet(
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: Tb.slate),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          if (onRetry != null) TbTextButton('Повторить', onPressed: onRetry),
        ]),
      );
}
