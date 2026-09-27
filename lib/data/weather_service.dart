import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app/env.dart';
import 'models.dart';
import 'stores.dart';

/// Погода для маршрута. Данные: Open-Meteo (без ключа).
/// Прогноз берётся сразу для трёх высот маршрута: старт, середина и верх.
/// Высоту не передаём: Open-Meteo сам берёт её из модели рельефа,
/// поэтому прогноз у старта и наверху разный.
class WeatherService {
  WeatherService(this._prefs);
  final SharedPreferences _prefs;
  final _mem = <String, WeatherReport>{};

  static const forecastDays = 16;
  static const _hourly = 'temperature_2m,precipitation,weather_code,wind_gusts_10m,cape';
  static const _daily =
      'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_gusts_10m_max,sunrise,sunset';

  /// Точки для прогноза: старт, промежуточная точка до вершины (если есть), верх.
  static List<(String, RoutePoint)> levelPoints(RouteInfo r) {
    final start = r.start, top = r.top;
    if (start == null || top == null) return const [];
    final topIndex = r.points.indexOf(top);
    final mids = [
      for (var i = 0; i < topIndex; i++)
        if (r.points[i].role == 'waypoint') r.points[i]
    ];
    return [
      ('Старт', start),
      if (mids.isNotEmpty) ('Середина', mids[mids.length ~/ 2]),
      ('Верх', top),
    ];
  }

  /// Прогноз на 16 дней. Кеш в памяти — 60 минут, копия на телефоне — для работы без сети.
  Future<WeatherReport> forecast(RouteInfo route, {bool force = false}) async {
    final pts = levelPoints(route);
    if (pts.isEmpty) throw WeatherError('У маршрута ещё нет проверенных координат.');

    final cached = _mem[route.id];
    if (!force && cached != null && !cached.fromCache && almatyNow().difference(cached.fetchedAt).inMinutes < 60) {
      return cached;
    }

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pts.map((p) => p.$2.lat.toStringAsFixed(5)).join(','),
      'longitude': pts.map((p) => p.$2.lon.toStringAsFixed(5)).join(','),
      'hourly': _hourly,
      'daily': _daily,
      'timezone': 'Asia/Almaty',
      'forecast_days': '$forecastDays',
      'wind_speed_unit': 'kmh',
    });

    try {
      final raw = await _get(uri);
      final at = almatyNow();
      final report = parse(route, raw, at);
      _prefs.setString('wx.${route.id}', raw);
      _prefs.setString('wx.${route.id}.at', at.toIso8601String());
      _mem[route.id] = report;
      return report;
    } catch (e) {
      final saved = savedFor(route);
      if (saved != null) return saved;
      if (e is WeatherError) rethrow;
      throw WeatherError('Нет связи, а сохранённого прогноза для этого маршрута нет.');
    }
  }

  /// Последний сохранённый прогноз (без сети). null — если его нет.
  WeatherReport? savedFor(RouteInfo route) {
    final raw = _prefs.getString('wx.${route.id}');
    final at = DateTime.tryParse(_prefs.getString('wx.${route.id}.at') ?? '');
    if (raw == null || at == null) return null;
    try {
      return parse(route, raw, at, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  /// Сырой ответ Open-Meteo и время загрузки — для офлайн-пакета похода.
  (String, DateTime)? rawFor(String routeId) {
    final raw = _prefs.getString('wx.$routeId');
    final at = DateTime.tryParse(_prefs.getString('wx.$routeId.at') ?? '');
    return raw == null || at == null ? null : (raw, at);
  }

  /// Разбор ответа Open-Meteo (одна или несколько точек).
  WeatherReport parse(RouteInfo route, String raw, DateTime fetchedAt, {bool fromCache = false}) {
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : [decoded];
    final pts = levelPoints(route);
    final levels = <LevelForecast>[
      for (var i = 0; i < list.length && i < pts.length; i++)
        LevelForecast(
          pts[i].$1,
          pts[i].$2.name,
          _num((list[i] as Map)['elevation']) ?? double.nan,
          _parseDays(Map<String, dynamic>.from(list[i] as Map)),
        ),
    ];
    if (levels.isEmpty) throw WeatherError('Погодный сервис вернул пустой ответ.');
    return WeatherReport(route.id, fetchedAt, levels, fromCache: fromCache);
  }

  /// Погода на конкретный день: прогноз, а если дата дальше горизонта —
  /// обычная погода в эти дни по данным последних 10 лет.
  Future<DayWeather> dayFor(RouteInfo route, DateTime date) async {
    final d = DateTime(date.year, date.month, date.day);
    final today = almatyToday();
    if (d.isBefore(today)) throw WeatherError('Эта дата уже прошла.');
    if (d.difference(today).inDays < forecastDays - 1) {
      final f = await forecast(route);
      final day = f.day(d);
      if (day != null) return day;
    }
    return typical(route, d);
  }

  Future<DayWeather> typical(RouteInfo route, DateTime date) async {
    final top = route.top;
    if (top == null) throw WeatherError('У маршрута ещё нет проверенных координат.');
    final end = DateTime(date.year - 1, date.month, date.day).add(const Duration(days: 3));
    final start = DateTime(date.year - 10, date.month, date.day).subtract(const Duration(days: 3));
    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': top.lat.toStringAsFixed(5),
      'longitude': top.lon.toStringAsFixed(5),
      'start_date': isoDate(start),
      'end_date': isoDate(end),
      'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum,wind_gusts_10m_max',
      'timezone': 'Asia/Almaty',
    });
    final j = jsonDecode(await _get(uri)) as Map<String, dynamic>;
    final daily = j['daily'] as Map<String, dynamic>;
    final times = (daily['time'] as List).cast<String>();
    final tMax = <double>[], tMin = <double>[], precip = <double>[], gust = <double>[];
    for (var i = 0; i < times.length; i++) {
      final t = DateTime.parse(times[i]);
      // окно ±3 дня вокруг той же даты в каждом году
      final same = DateTime(t.year, date.month, date.day);
      if (t.difference(same).inDays.abs() > 3) continue;
      final a = _num(daily['temperature_2m_max'][i]), b = _num(daily['temperature_2m_min'][i]);
      if (a == null || b == null) continue;
      tMax.add(a);
      tMin.add(b);
      precip.add(_num(daily['precipitation_sum'][i]) ?? 0);
      gust.add(_num(daily['wind_gusts_10m_max'][i]) ?? 0);
    }
    if (tMax.isEmpty) throw WeatherError('Не удалось получить данные прошлых лет.');
    double avg(List<double> v) => v.reduce((x, y) => x + y) / v.length;
    final rainyShare = precip.where((p) => p >= 1).length / precip.length;
    final (sunrise, sunset) = sunTimes(date, top.lat, top.lon);
    final warnings = <String>[
      'Это не прогноз, а обычная погода в эти дни за последние 10 лет. Точный прогноз появится примерно за две недели.',
      if (rainyShare >= 0.4) 'В эти даты осадки бывают часто: примерно в ${(rainyShare * 100).round()}% дней.',
      if (avg(tMin) <= 0) 'Ночью и утром наверху обычно мороз.',
    ];
    return DayWeather(
      date: date,
      code: rainyShare >= 0.4 ? 61 : 2,
      tMin: avg(tMin),
      tMax: avg(tMax),
      precipSum: avg(precip),
      gustMax: avg(gust),
      sunrise: sunrise,
      sunset: sunset,
      hours: const [],
      typical: true,
      warnings: warnings,
      verdict: DayVerdict.unknown,
    );
  }

  // ───────────── разбор ответа ─────────────

  List<DayWeather> _parseDays(Map<String, dynamic> j) {
    final h = j['hourly'] as Map<String, dynamic>;
    final hTimes = (h['time'] as List).cast<String>();
    final hours = <HourWeather>[
      for (var i = 0; i < hTimes.length; i++)
        HourWeather(
          DateTime.parse(hTimes[i]),
          _num(h['temperature_2m'][i]) ?? double.nan,
          _num(h['precipitation'][i]) ?? 0,
          (_num(h['weather_code'][i]) ?? 0).toInt(),
          _num(h['wind_gusts_10m'][i]) ?? 0,
          _num(h['cape'][i]) ?? 0,
        )
    ];

    final d = j['daily'] as Map<String, dynamic>;
    final dTimes = (d['time'] as List).cast<String>();
    final days = <DayWeather>[];
    for (var i = 0; i < dTimes.length; i++) {
      final date = DateTime.parse(dTimes[i]);
      final dayHours = hours
          .where((x) => x.time.year == date.year && x.time.month == date.month && x.time.day == date.day)
          .toList();
      final daylight = dayHours.where((x) => x.time.hour >= 7 && x.time.hour <= 20).toList();
      final warnings = <String>[];
      final thunder = daylight.where((x) => x.thunder).toList();
      final windy = daylight.where((x) => x.strongWind).toList();
      final gustMax = _num(d['wind_gusts_10m_max'][i]) ?? 0;
      final precipSum = _num(d['precipitation_sum'][i]) ?? 0;
      final tMin = _num(d['temperature_2m_min'][i]) ?? double.nan;

      if (thunder.isNotEmpty) warnings.add('Возможна гроза с ${hhmm(thunder.first.time)}.');
      if (windy.isNotEmpty) warnings.add('Порывы ветра до ${gustMax.round()} км/ч.');
      if (precipSum >= 1) warnings.add('Осадки: ${precipSum.toStringAsFixed(1)} мм за день.');
      if (tMin <= 0) warnings.add('Мороз до ${tMin.round()} °C — возможен лёд.');

      final bad = thunder.any((x) => x.time.hour >= 9 && x.time.hour <= 17) || gustMax >= 70 || precipSum >= 10;
      days.add(DayWeather(
        date: date,
        code: (_num(d['weather_code'][i]) ?? 0).toInt(),
        tMin: tMin,
        tMax: _num(d['temperature_2m_max'][i]) ?? double.nan,
        precipSum: precipSum,
        gustMax: gustMax,
        sunrise: DateTime.parse(d['sunrise'][i]),
        sunset: DateTime.parse(d['sunset'][i]),
        hours: dayHours,
        typical: false,
        warnings: warnings,
        verdict: bad ? DayVerdict.bad : (warnings.isEmpty ? DayVerdict.good : DayVerdict.caution),
      ));
    }
    return days;
  }

  Future<String> _get(Uri uri) async {
    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http.get(uri).timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) return r.body;
        last = 'HTTP ${r.statusCode}';
      } catch (e) {
        last = e;
      }
      await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw WeatherError('Погодный сервис не ответил ($last).');
  }

  static double? _num(dynamic v) => v == null ? null : (v as num).toDouble();
}

class WeatherError implements Exception {
  final String message;
  WeatherError(this.message);
  @override
  String toString() => message;
}

final weatherServiceProvider = Provider((ref) => WeatherService(ref.read(prefsProvider)));

final forecastProvider = FutureProvider.family<WeatherReport, String>((ref, routeId) async {
  final routes = await ref.watch(routesProvider.future);
  final route = routes.firstWhere((r) => r.id == routeId);
  return ref.read(weatherServiceProvider).forecast(route);
});

// ───────────── подписи и иконки кодов WMO ─────────────

String weatherText(int code) => switch (code) {
      0 => 'Ясно',
      1 => 'Почти ясно',
      2 => 'Переменная облачность',
      3 => 'Пасмурно',
      45 || 48 => 'Туман',
      >= 51 && <= 57 => 'Морось',
      >= 61 && <= 67 => 'Дождь',
      >= 71 && <= 77 => 'Снег',
      >= 80 && <= 82 => 'Ливни',
      85 || 86 => 'Снегопад',
      >= 95 => 'Гроза',
      _ => 'Облачно',
    };

IconData weatherIcon(int code) => switch (code) {
      0 || 1 => Icons.wb_sunny_rounded,
      2 || 3 => Icons.cloud_rounded,
      45 || 48 => Icons.cloud_queue_rounded,
      >= 51 && <= 67 => Icons.water_drop_rounded,
      >= 80 && <= 82 => Icons.water_drop_rounded,
      >= 71 && <= 77 => Icons.ac_unit_rounded,
      85 || 86 => Icons.ac_unit_rounded,
      >= 95 => Icons.thunderstorm_rounded,
      _ => Icons.cloud_rounded,
    };

String tempText(double t) => t.isNaN ? '—' : '${t.round() > 0 ? '+' : ''}${t.round()}°';

/// Небольшой helper для карточек: округлённое число без минус-нуля.
int roundSafe(double v) => v.isNaN ? 0 : math.max(-99, v.round());
