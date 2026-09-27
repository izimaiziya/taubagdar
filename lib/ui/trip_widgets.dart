import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/env.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../data/trip_package.dart';
import '../data/weather_service.dart';
import 'widgets.dart';

// ─────────────────────────── Кольцо готовности ───────────────────────────

/// Четыре сектора: рюкзак, контакты, прогноз, пакет. Зелёный — готово.
class ReadinessRing extends StatelessWidget {
  const ReadinessRing(this.items, {super.key, this.size = 64});
  final List<ReadinessItem> items;
  final double size;

  @override
  Widget build(BuildContext context) {
    final done = items.where((i) => i.ok).length;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(items.map((i) => i.ok).toList(), size * .1),
        child: Center(
          child: Text('$done/${items.length}',
              style: TextStyle(
                  fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: size * .24, color: Tb.night)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ok, this.stroke);
  final List<bool> ok;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    if (ok.isEmpty) return;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    const gap = 0.14;
    final sweep = 2 * math.pi / ok.length;
    for (var i = 0; i < ok.length; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = ok[i] ? Tb.safe : Tb.mist
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.ok.toString() != ok.toString();
}

/// Кольцо + расшифровка по пунктам.
class ReadinessPanel extends StatelessWidget {
  const ReadinessPanel(this.items, {super.key});
  final List<ReadinessItem> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Sheet(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ReadinessRing(items, size: 76),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(i.ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20, color: i.ok ? Tb.safe : Tb.slate),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${i.title}. ', style: t.titleMedium?.copyWith(fontSize: 15)),
                      TextSpan(text: i.hint, style: t.bodySmall),
                    ])),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────── Календарь погоды ───────────────────────────

/// 16 дней прогноза, каждый день окрашен: зелёный — хороший, жёлтый — с оговорками, красный — лучше не идти.
class WeatherCalendar extends StatelessWidget {
  const WeatherCalendar({super.key, required this.days, required this.selected, required this.onSelect});
  final List<DayWeather> days;
  final DateTime? selected;
  final ValueChanged<DayWeather> onSelect;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final first = days.first.date;
    final lead = first.weekday - 1; // пн = 0
    final cells = <DayWeather?>[...List.filled(lead, null), ...days];
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Column(children: [
      Row(children: [
        for (final n in names)
          Expanded(
            child: Center(
              child: Text(n,
                  style: const TextStyle(fontFamily: Tb.body, fontSize: 12.5, fontWeight: FontWeight.w600, color: Tb.slate)),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: .78,
        children: [
          for (final d in cells)
            if (d == null)
              const SizedBox.shrink()
            else
              _DayCell(d, selected: selected != null && sameDay(selected!, d.date), onTap: () => onSelect(d)),
        ],
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final v in [DayVerdict.good, DayVerdict.caution, DayVerdict.bad]) ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: verdictColor(v), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(verdictText(v), style: const TextStyle(fontFamily: Tb.body, fontSize: 12.5, color: Tb.slate)),
          const SizedBox(width: 14),
        ],
      ]),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell(this.d, {required this.selected, required this.onTap});
  final DayWeather d;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = verdictColor(d.verdict);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: c.withValues(alpha: selected ? 1 : .14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.date.day}',
              style: TextStyle(
                  fontFamily: Tb.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: selected ? Colors.white : Tb.night)),
          Icon(weatherIcon(d.code), size: 15, color: selected ? Colors.white : c),
          Text(tempText(d.tMax),
              style: TextStyle(fontFamily: Tb.body, fontSize: 11.5, color: selected ? Colors.white : Tb.ink)),
        ]),
      ),
    );
  }
}

// ─────────────────────────── Погода на трёх высотах ───────────────────────────

/// Таблица: строки — высоты маршрута, столбцы — часы с 6 до 21 через 3 часа.
class LevelsTable extends StatelessWidget {
  const LevelsTable({super.key, required this.report, required this.date, this.fromHour = 6});
  final WeatherReport report;
  final DateTime date;
  final int fromHour;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hours = [for (var h = fromHour - fromHour % 3; h <= 21; h += 3) h];
    final levels = report.levels.reversed.toList(); // верх сверху

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(58),
        columnWidths: const {0: FixedColumnWidth(104)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            const SizedBox.shrink(),
            for (final h in hours)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(child: Text('$h:00', style: t.bodySmall?.copyWith(fontSize: 12))),
              ),
          ]),
          for (final l in levels)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.label, style: t.titleMedium?.copyWith(fontSize: 14.5)),
                  Text(l.elevation.isNaN ? '' : '${l.elevation.round()} м', style: t.bodySmall?.copyWith(fontSize: 12)),
                ]),
              ),
              for (final h in hours) _HourCell(_hour(l, h)),
            ]),
        ],
      ),
    );
  }

  HourWeather? _hour(LevelForecast l, int h) {
    final d = l.day(date);
    if (d == null) return null;
    for (final x in d.hours) {
      if (x.time.hour == h) return x;
    }
    return null;
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell(this.h);
  final HourWeather? h;

  @override
  Widget build(BuildContext context) {
    final x = h;
    if (x == null) return const Center(child: Text('—'));
    final danger = x.thunder || x.gustKmh >= 50;
    final warn = x.rain || x.freezing;
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: danger
            ? Tb.danger.withValues(alpha: .14)
            : warn
                ? Tb.caution.withValues(alpha: .14)
                : Tb.ice,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Icon(weatherIcon(x.code), size: 17, color: danger ? Tb.danger : Tb.sky),
        Text(tempText(x.tempC),
            style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w700, fontSize: 13.5, color: Tb.night)),
        Text('${x.gustKmh.round()}',
            style: TextStyle(fontFamily: Tb.body, fontSize: 11, color: x.gustKmh >= 50 ? Tb.danger : Tb.slate)),
      ]),
    );
  }
}

/// Подпись к таблице высот.
String levelsCaption(WeatherReport r) => r.fromCache
    ? 'Без связи: прогноз от ${DateFormat('d MMM, HH:mm', 'ru').format(r.fetchedAt)}. Нижняя цифра — порывы ветра, км/ч.'
    : 'Open-Meteo, обновлено в ${hhmm(r.fetchedAt)}. Нижняя цифра — порывы ветра, км/ч.';
