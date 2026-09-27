import 'dart:math' as math;

import '../app/env.dart';
import '../data/models.dart';

/// Вся логика безопасности — здесь, в обычном коде с тестами.
/// ИИ только вызывает эти функции и пересказывает результат.
class Planner {
  const Planner(this.profile);
  final UserProfile profile;

  // ───────────── подбор маршрута ─────────────

  /// Возвращает подходящие маршруты и причины, почему остальные не подошли.
  (List<RouteInfo> fit, Map<String, String> rejected) searchRoutes(
    List<RouteInfo> all, {
    double? maxHours,
    bool withKids = false,
  }) {
    final fit = <RouteInfo>[];
    final rejected = <String, String>{};
    for (final r in all) {
      final reason = whyNot(r, maxHours: maxHours, withKids: withKids);
      if (reason == null) {
        fit.add(r);
      } else {
        rejected[r.id] = reason;
      }
    }
    fit.sort((a, b) => a.difficulty.compareTo(b.difficulty));
    return (fit, rejected);
  }

  /// null — маршрут подходит. Иначе — понятная причина.
  String? whyNot(RouteInfo r, {double? maxHours, bool withKids = false}) {
    if (!r.verified) return 'данные маршрута ещё проверяются';
    if (r.access != 'open') return 'доступ к маршруту сейчас ограничен или не подтверждён';
    if (r.minExperience > profile.expLevel) return 'нужен опыт выше вашего';
    final hours = r.hoursMax * profile.paceFactor;
    if (maxHours != null && hours > maxHours + 0.5) {
      return 'займёт около ${hours.toStringAsFixed(1)} ч, а у вас ${maxHours.toStringAsFixed(0)} ч';
    }
    if (withKids && (r.maxEleM ?? 0) > 2800) return 'слишком высоко для похода с детьми';
    if (profile.maxAltitude <= 0 && (r.maxEleM ?? 0) >= 3000 && profile.expLevel < 2) {
      return 'поднимается до 3000 м, а вы ещё не бывали так высоко';
    }
    return null;
  }

  // ───────────── план дня ─────────────

  /// Время разворота = дедлайн минус спуск. Дедлайн — раньшее из
  /// «закат минус 45 минут» и «начало грозы по прогнозу».
  DayPlan dayPlan(RouteInfo r, DayWeather w, {DateTime? preferredStart}) {
    final date = w.date;
    final total = Duration(minutes: ((r.hoursMin + r.hoursMax) / 2 * profile.paceFactor * 60).round());
    final up = Duration(minutes: (total.inMinutes * 0.58).round()); // подъём дольше спуска
    final down = total - up;

    var deadline = w.sunset.subtract(const Duration(minutes: 45));
    var factor = 'закат в ${hhmm(w.sunset)}';
    final storm = w.firstThunder;
    if (storm != null && storm.isBefore(deadline)) {
      deadline = storm;
      factor = 'гроза по прогнозу с ${hhmm(storm)}';
    }

    // Старт: через час после восхода, не раньше 7:00, округляем до 30 минут.
    var start = preferredStart ?? w.sunrise.add(const Duration(hours: 1));
    final seven = DateTime(date.year, date.month, date.day, 7);
    if (start.isBefore(seven)) start = seven;
    start = DateTime(start.year, start.month, start.day, start.hour, start.minute < 30 ? 30 : 0)
        .add(Duration(hours: start.minute < 30 ? 0 : 1));

    // Если с таким стартом не успеваем — сдвигаем старт раньше, но не раньше восхода.
    var returnBy = start.add(total);
    if (returnBy.isAfter(deadline)) {
      final earliest = w.sunrise.add(const Duration(minutes: 20));
      final needed = deadline.subtract(total);
      start = needed.isAfter(earliest) ? needed : earliest;
      start = DateTime(start.year, start.month, start.day, start.hour, (start.minute ~/ 15) * 15);
      returnBy = start.add(total);
    }

    final turnaround = deadline.subtract(down);
    final plannedTop = start.add(up);
    final feasible = !returnBy.isAfter(deadline);

    final notes = <String>[
      'Время рассчитано для вашего темпа (×${profile.paceFactor.toStringAsFixed(2)} к среднему) и уточнится в походе.',
      if (!feasible) 'Даже при раннем старте вы не успеваете до ограничения ($factor). Лучше выбрать другой день или маршрут короче.',
      if (turnaround.isBefore(plannedTop))
        'По расчёту к ${hhmm(turnaround)} вы ещё не дойдёте до верхней точки. Разворачивайтесь в это время, где бы вы ни были.',
      if (w.typical) 'Погода на этот день пока примерная. Я пересчитаю план, когда появится прогноз.',
      ...w.warnings.where((s) => !s.startsWith('Это не прогноз')),
    ];

    return DayPlan(
      routeId: r.id,
      routeName: r.name,
      date: date,
      start: start,
      turnaround: turnaround,
      returnBy: returnBy,
      sunset: w.sunset,
      limitingFactor: factor,
      feasible: feasible,
      timeline: [
        TimelineItem(start.subtract(const Duration(hours: 1)), 'Выезд из города', note: 'Дорога до старта занимает время — заложите час.'),
        TimelineItem(start, 'Старт на тропе', note: r.start?.name),
        for (final (p, share) in _waypointShares(r))
          TimelineItem(start.add(Duration(minutes: (up.inMinutes * share).round())), p.name, note: 'примерно'),
        TimelineItem(plannedTop, 'Верхняя точка по плану', note: r.top?.name),
        TimelineItem(turnaround, 'Разворот не позднее', note: 'Ограничение: $factor', key: true),
        TimelineItem(returnBy, 'Возвращение к старту'),
        TimelineItem(w.sunset, 'Закат'),
      ]..sort((a, b) => a.time.compareTo(b.time)),
      notes: notes,
    );
  }

  /// Промежуточные точки до вершины и доля пути до них (по прямой между точками).
  static List<(RoutePoint, double)> _waypointShares(RouteInfo r) {
    final top = r.top;
    if (top == null) return const [];
    final upTo = r.points.sublist(0, r.points.indexOf(top) + 1);
    if (upTo.length < 3) return const [];
    final legs = <double>[0];
    for (var i = 1; i < upTo.length; i++) {
      legs.add(legs.last + _km(upTo[i - 1], upTo[i]));
    }
    final total = legs.last;
    if (total <= 0) return const [];
    return [
      for (var i = 1; i < upTo.length - 1; i++)
        if (upTo[i].role == 'waypoint') (upTo[i], legs[i] / total)
    ];
  }

  static double _km(RoutePoint a, RoutePoint b) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  // ───────────── чек-лист ─────────────

  List<ChecklistItem> checklist(RouteInfo r, DayWeather w) {
    final hours = r.hoursMax * profile.paceFactor;
    final water = (hours * 0.35).clamp(1.5, 3.0);
    final month = w.date.month;
    final gear = profile.gear;
    ChecklistItem item(String id, String group, String title, String why, {bool critical = false, String? gearKey}) =>
        ChecklistItem(id, group, title, why, critical: critical, owned: gearKey == null || gear.contains(gearKey));

    return [
      // Безопасность
      item('phone', 'Безопасность', 'Заряженный телефон', 'Это ваша карта, связь и SOS. Зарядите до 100%.', critical: true),
      item('powerbank', 'Безопасность', 'Пауэрбанк и кабель', 'GPS в горах быстро садит батарею.', critical: true, gearKey: 'powerbank'),
      item('headlamp', 'Безопасность', 'Налобный фонарь', 'Даже если планируете вернуться засветло.', critical: true, gearKey: 'headlamp'),
      item('firstaid', 'Безопасность', 'Аптечка', 'Пластыри, бинт, обезболивающее и ваши лекарства.', critical: true, gearKey: 'firstaid'),
      item('whistle', 'Безопасность', 'Свисток', 'Слышно дальше голоса, если понадобится помощь.'),
      // Одежда
      item('boots', 'Одежда', r.difficulty >= 3 ? 'Треккинговые ботинки' : 'Удобная обувь с хорошей подошвой',
          r.difficulty >= 3 ? 'На маршруте есть крутые и сыпучие участки.' : 'Кроссовки для города скользят на тропе.',
          critical: r.difficulty >= 3, gearKey: r.difficulty >= 3 ? 'boots' : null),
      item('warm', 'Одежда', 'Тёплый слой (флис или лёгкий пуховик)',
          w.tMin.isNaN ? 'В горах холоднее, чем в городе.' : 'Наверху ожидается до ${w.tMin.round()} °C.', critical: true),
      item('shell', 'Одежда', 'Дождевик или мембранная куртка',
          w.precipSum >= 1 ? 'По прогнозу осадки.' : 'Погода в горах меняется быстро.', critical: true, gearKey: 'shell'),
      if (!w.tMin.isNaN && w.tMin < 5) item('hat', 'Одежда', 'Шапка и перчатки', 'Наверху до ${w.tMin.round()} °C.'),
      if ((r.maxEleM ?? 0) >= 2500 || w.code <= 1)
        item('sun', 'Одежда', 'Солнцезащитные очки и крем', 'На высоте солнце обжигает быстрее.'),
      if (r.difficulty >= 3 || profile.health.contains('knees'))
        item('poles', 'Одежда', 'Треккинговые палки', 'Берегут колени на длинном спуске.', gearKey: 'poles'),
      if (month >= 4 && month <= 7)
        item('ticks', 'Одежда', 'Закрытая светлая одежда и репеллент от клещей',
            'Весна и начало лета — сезон клещей. Штаны заправьте в носки.', critical: true),
      // Вода и еда
      item('water', 'Вода и еда', 'Вода: ${water.toStringAsFixed(1)} л на человека', 'Рассчитано по длительности маршрута.', critical: true),
      item('food', 'Вода и еда', 'Перекус', 'Орехи, сухофрукты, батончики — есть понемногу каждый час.'),
      if (!w.tMin.isNaN && w.tMin < 8) item('thermos', 'Вода и еда', 'Термос с горячим чаем', 'Согревает на привале.', gearKey: 'thermos'),
      // Документы и деньги
      item('id', 'Документы и деньги', 'Удостоверение личности', 'Может понадобиться на КПП и спасателям.'),
      item('fee', 'Документы и деньги', 'Оплата входа в нацпарк', r.feeNote.isEmpty ? 'Проверьте правила на КПП.' : r.feeNote),
      if (profile.company == Company.solo && profile.expLevel == 0)
        item('buddy', 'Безопасность', 'Напарник', 'Первый поход лучше не проходить в одиночку.', critical: true),
      if (profile.ageGroup == 'under18')
        item('adult', 'Безопасность', 'Взрослый сопровождающий', 'Идти в горы до 18 лет — только со взрослыми.', critical: true),
    ];
  }
}

/// Текст уведомления ДЧС: пользователь копирует его в eQonaq, email или диктует по 112.
String dchsNotificationText(UserProfile p, Trip t, RouteInfo? r) {
  final d = t.date;
  return [
    'Уведомление о туристическом походе',
    'ФИО: ${p.name}',
    'Телефон: ${p.phone}',
    'Объект: ${t.routeName}${r?.start != null ? ' (старт: ${r!.start!.name})' : ''}',
    'Дата: ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
    'Выход: ${hhmm(t.start)}, планируемое возвращение: ${hhmm(t.returnBy)}',
    if (r?.lengthKm != null) 'Протяжённость: около ${r!.lengthKm!.toStringAsFixed(0)} км',
    'Ночёвка: не планируется',
  ].join('\n');
}
