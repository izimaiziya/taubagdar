import 'package:flutter_test/flutter_test.dart';
import 'package:taubagdar/app/env.dart';
import 'package:taubagdar/alan/planner.dart';
import 'package:taubagdar/data/models.dart';

RouteInfo _route() => const RouteInfo(
      id: 'test',
      name: 'Тест',
      subtitle: '',
      difficulty: 2,
      minExperience: 0,
      hoursMin: 5,
      hoursMax: 7,
      maxEleM: null,
      lengthKm: null,
      exposedRidge: false,
      access: 'open',
      accessVerifiedAt: null,
      verified: true,
      points: [RoutePoint('Старт', 'start', 43.128, 76.906), RoutePoint('Верх', 'top', 43.142, 77.004)],
      howToGet: '',
      risks: [],
      feeNote: '',
      sources: [],
    );

DayWeather _day({List<HourWeather> hours = const []}) => DayWeather(
      date: DateTime(2026, 9, 27),
      code: 1,
      tMin: 3,
      tMax: 14,
      precipSum: 0,
      gustMax: 20,
      sunrise: DateTime(2026, 9, 27, 5, 44),
      sunset: DateTime(2026, 9, 27, 17, 42),
      hours: hours,
      typical: false,
      warnings: const [],
      verdict: DayVerdict.good,
    );

void main() {
  test('восход и закат для Алматы 27.09', () {
    final (rise, fall) = sunTimes(DateTime(2026, 9, 27), 43.14239, 77.00433);
    expect(hhmm(rise), '05:44');
    expect(hhmm(fall), '17:42');
  });

  test('разворот раньше заката и возвращение до дедлайна', () {
    const p = UserProfile(experience: Experience.easyTrails, fitness: 1);
    final plan = const Planner(p).dayPlan(_route(), _day());
    expect(plan.turnaround.isBefore(plan.sunset), isTrue);
    expect(plan.returnBy.isAfter(plan.sunset.subtract(const Duration(minutes: 45))), isFalse);
  });

  test('гроза сдвигает дедлайн', () {
    const p = UserProfile(experience: Experience.regular, fitness: 2);
    final storm = HourWeather(DateTime(2026, 9, 27, 14), 10, 2, 95, 40, 1500);
    final plan = const Planner(p).dayPlan(_route(), _day(hours: [storm]));
    expect(plan.limitingFactor, contains('гроза'));
    expect(plan.turnaround.isBefore(DateTime(2026, 9, 27, 14)), isTrue);
  });

  test('непроверенный маршрут не предлагается', () {
    const p = UserProfile(experience: Experience.alpine);
    final r = _route();
    final unverified = RouteInfo(
      id: 'x', name: 'X', subtitle: '', difficulty: 3, minExperience: 1, hoursMin: 6, hoursMax: 7,
      maxEleM: 3053, lengthKm: 16, exposedRidge: true, access: 'open', accessVerifiedAt: null,
      verified: false, points: const [], howToGet: '', risks: const [], feeNote: '', sources: const [],
    );
    final (fit, rejected) = const Planner(p).searchRoutes([r, unverified]);
    expect(fit.map((e) => e.id), ['test']);
    expect(rejected['x'], contains('проверяются'));
  });
}
