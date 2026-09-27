import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/env.dart';
import '../core/iter.dart';
import 'models.dart';
import 'stores.dart';
import 'weather_service.dart';

/// Всё, что нужно в горах без связи: прогноз по трём высотам, план и контакты.
/// Маршрут, инструкции первой помощи и чек-лист уже лежат в приложении.
class TripPackage {
  final String tripId;
  final DateTime createdAt;
  final String forecastRaw; // ответ Open-Meteo как есть
  final DateTime forecastAt;
  final List<String> contacts; // «Имя, телефон»
  final int checksum;

  const TripPackage({
    required this.tripId,
    required this.createdAt,
    required this.forecastRaw,
    required this.forecastAt,
    required this.contacts,
    required this.checksum,
  });

  /// Контрольная сумма FNV-1a по содержимому пакета: ловит повреждённые или неполные данные.
  static int checksumOf(String tripId, String forecastRaw, DateTime forecastAt, List<String> contacts) {
    final bytes = utf8.encode([tripId, forecastRaw, forecastAt.toIso8601String(), ...contacts].join('\u0001'));
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  bool get intact => checksumOf(tripId, forecastRaw, forecastAt, contacts) == checksum;

  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'createdAt': createdAt.toIso8601String(),
        'forecastRaw': forecastRaw,
        'forecastAt': forecastAt.toIso8601String(),
        'contacts': contacts,
        'checksum': checksum,
      };

  factory TripPackage.fromJson(Map<String, dynamic> j) => TripPackage(
        tripId: j['tripId'],
        createdAt: DateTime.parse(j['createdAt']),
        forecastRaw: j['forecastRaw'],
        forecastAt: DateTime.parse(j['forecastAt']),
        contacts: (j['contacts'] as List).cast<String>(),
        checksum: j['checksum'],
      );
}

/// Одна проверка перед выходом на тропу.
class PackageCheck {
  final String title;
  final bool ok;
  final String detail;
  const PackageCheck(this.title, this.ok, this.detail);
}

class PackageNotifier extends Notifier<Map<String, TripPackage>> {
  static const _prefix = 'pkg.';

  @override
  Map<String, TripPackage> build() {
    final prefs = ref.read(prefsProvider);
    final out = <String, TripPackage>{};
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      try {
        final p = TripPackage.fromJson(jsonDecode(prefs.getString(k)!));
        out[p.tripId] = p;
      } catch (_) {/* повреждённый пакет просто не показываем — проверка предложит скачать заново */}
    }
    return out;
  }

  /// Скачать пакет одним нажатием: свежий прогноз + контакты, с контрольной суммой.
  Future<TripPackage> download(Trip trip) async {
    final routes = await ref.read(routesProvider.future);
    final route = routes.where((r) => r.id == trip.routeId).firstOrNone;
    if (route == null || !route.plannable) throw WeatherError('Маршрут не найден или ещё не проверен.');

    final wx = ref.read(weatherServiceProvider);
    final report = await wx.forecast(route, force: true);
    if (report.fromCache) throw WeatherError('Нет связи. Скачайте пакет, пока есть интернет.');
    final raw = wx.rawFor(route.id);
    if (raw == null) throw WeatherError('Не удалось сохранить прогноз.');

    final contacts = ref.read(profileProvider).contacts.map((c) => '${c.name}, ${c.phone}').toList();
    final pkg = TripPackage(
      tripId: trip.id,
      createdAt: almatyNow(),
      forecastRaw: raw.$1,
      forecastAt: raw.$2,
      contacts: contacts,
      checksum: TripPackage.checksumOf(trip.id, raw.$1, raw.$2, contacts),
    );
    await ref.read(prefsProvider).setString('$_prefix${trip.id}', jsonEncode(pkg.toJson()));
    state = {...state, trip.id: pkg};
    return pkg;
  }

  void remove(String tripId) {
    ref.read(prefsProvider).remove('$_prefix$tripId');
    state = {...state}..remove(tripId);
  }

  /// Прогноз из пакета — работает без сети.
  WeatherReport? forecastFrom(TripPackage p, RouteInfo route) {
    try {
      return ref.read(weatherServiceProvider).parse(route, p.forecastRaw, p.forecastAt, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  /// Проверка целостности данных перед выходом на тропу.
  List<PackageCheck> verify(Trip trip, RouteInfo? route, UserProfile profile) {
    final p = state[trip.id];
    final checks = <PackageCheck>[];

    checks.add(route != null && route.plannable
        ? PackageCheck('Маршрут', true, '${route.points.length} ключевые точки с координатами')
        : const PackageCheck('Маршрут', false, 'Нет проверенных координат'));

    if (p == null) {
      checks.add(const PackageCheck('Пакет', false, 'Ещё не скачан'));
      return checks;
    }

    checks.add(p.intact
        ? const PackageCheck('Целостность', true, 'Контрольная сумма совпадает')
        : const PackageCheck('Целостность', false, 'Данные повреждены — скачайте заново'));

    final report = route == null ? null : forecastFrom(p, route);
    final day = report?.day(trip.date);
    final age = almatyNow().difference(p.forecastAt);
    if (report == null) {
      checks.add(const PackageCheck('Прогноз', false, 'Не читается — скачайте заново'));
    } else if (day == null) {
      checks.add(const PackageCheck('Прогноз', false, 'Не покрывает дату похода'));
    } else if (age.inHours > 24) {
      checks.add(PackageCheck('Прогноз', false, 'Устарел: скачан ${age.inHours} ч назад'));
    } else {
      checks.add(PackageCheck('Прогноз', true, '${report.levels.length} высоты, скачан ${_ago(age)}'));
    }

    if (day != null) {
      final okTime = trip.turnaround.isBefore(day.sunset);
      checks.add(PackageCheck('План', okTime,
          okTime ? 'Разворот ${hhmm(trip.turnaround)}, закат ${hhmm(day.sunset)}' : 'Разворот позже заката — перепланируйте'));
    }

    checks.add(profile.contacts.isNotEmpty
        ? PackageCheck('Контакты', true, profile.contacts.map((c) => c.name).join(', '))
        : const PackageCheck('Контакты', false, 'Некому сообщить, если вы не вернётесь'));
    return checks;
  }

  static String _ago(Duration d) => d.inMinutes < 60 ? '${d.inMinutes} мин назад' : '${d.inHours} ч назад';
}

final packagesProvider = NotifierProvider<PackageNotifier, Map<String, TripPackage>>(PackageNotifier.new);

// ─────────────────────────── Кольцо готовности ───────────────────────────

class ReadinessItem {
  final String title;
  final bool ok;
  final String hint;
  const ReadinessItem(this.title, this.ok, this.hint);
}

/// Четыре сектора кольца: чек-лист, контакты, свежий прогноз, пакет маршрута.
List<ReadinessItem> readinessOf(Ref ref, Trip trip) {
  final profile = ref.watch(profileProvider);
  final pkg = ref.watch(packagesProvider)[trip.id];
  final daysLeft = trip.date.difference(almatyToday()).inDays;
  final fresh = pkg != null && almatyNow().difference(pkg.forecastAt).inHours <= 24;
  return [
    ReadinessItem('Рюкзак', trip.criticalLeft == 0,
        trip.criticalLeft == 0 ? 'Всё важное собрано' : 'Осталось важных вещей: ${trip.criticalLeft}'),
    ReadinessItem('Контакты', profile.contacts.isNotEmpty,
        profile.contacts.isNotEmpty ? 'Близкие узнают, если что-то случится' : 'Добавьте близкого человека'),
    ReadinessItem('Прогноз', fresh,
        fresh ? 'Свежий, для трёх высот' : (daysLeft > 14 ? 'Появится за 2 недели до похода' : 'Обновите накануне похода')),
    ReadinessItem('Пакет', pkg != null && pkg.intact,
        pkg == null ? 'Скачайте для работы без связи' : (pkg.intact ? 'Скачан и проверен' : 'Повреждён — скачайте заново')),
  ];
}

final readinessProvider = Provider.family<List<ReadinessItem>, String>((ref, tripId) {
  final trip = ref.watch(tripsProvider).where((t) => t.id == tripId).firstOrNone;
  return trip == null ? const [] : readinessOf(ref, trip);
});
