import 'dart:math' as math;
import '../core/iter.dart';

// ─────────────────────────── Профиль ───────────────────────────

enum Experience { never, easyTrails, regular, alpine }

enum Company { solo, friends, family, guide }

class EmergencyContact {
  final String name;
  final String relation;
  final String phone;
  final String inviteToken;
  final bool verified; // true только после подтверждения ботом на сервере

  const EmergencyContact({
    required this.name,
    required this.relation,
    required this.phone,
    required this.inviteToken,
    this.verified = false,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'relation': relation, 'phone': phone, 'token': inviteToken, 'verified': verified};

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        name: j['name'] ?? '',
        relation: j['relation'] ?? '',
        phone: j['phone'] ?? '',
        inviteToken: j['token'] ?? newToken(),
        verified: j['verified'] == true,
      );

  static String newToken() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = math.Random.secure();
    return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

class UserProfile {
  final bool introSeen;
  final bool registered;
  final String name;
  final String email;
  final String phone;
  final String ageGroup; // under18 | 18-35 | 36-55 | 55+
  final Experience? experience;
  final int maxAltitude; // 0: <2000, 1: 2000–3000, 2: >3000, -1: не знаю
  final int fitness; // 0 слабая, 1 средняя, 2 хорошая
  final Company? company;
  final Set<String> gear;
  final Set<String> health;
  final bool healthVisibleToRescuers;
  final List<EmergencyContact> contacts;

  const UserProfile({
    this.introSeen = false,
    this.registered = false,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.ageGroup = '',
    this.experience,
    this.maxAltitude = -1,
    this.fitness = 1,
    this.company,
    this.gear = const {},
    this.health = const {},
    this.healthVisibleToRescuers = false,
    this.contacts = const [],
  });

  int get expLevel => experience?.index ?? 0;

  /// Во сколько раз человек медленнее «среднего туриста» из описаний маршрутов.
  double get paceFactor {
    const byExp = [1.25, 1.1, 1.0, 0.92];
    const byFit = [1.12, 1.0, 0.93];
    return byExp[expLevel] * byFit[fitness.clamp(0, 2)];
  }

  String get levelTitle => switch (expLevel) {
        0 => 'Новичок',
        1 => 'Любитель',
        2 => 'Опытный',
        _ => 'Альпинист',
      };

  String get levelHint => switch (expLevel) {
        0 => 'Лёгкие маршруты до 7 часов, лучше не в одиночку',
        1 => 'Маршруты средней сложности, высоты до 3000 м',
        2 => 'Сложные однодневные маршруты',
        _ => 'Все маршруты каталога',
      };

  UserProfile copyWith({
    bool? introSeen,
    bool? registered,
    String? name,
    String? email,
    String? phone,
    String? ageGroup,
    Experience? experience,
    int? maxAltitude,
    int? fitness,
    Company? company,
    Set<String>? gear,
    Set<String>? health,
    bool? healthVisibleToRescuers,
    List<EmergencyContact>? contacts,
  }) =>
      UserProfile(
        introSeen: introSeen ?? this.introSeen,
        registered: registered ?? this.registered,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        ageGroup: ageGroup ?? this.ageGroup,
        experience: experience ?? this.experience,
        maxAltitude: maxAltitude ?? this.maxAltitude,
        fitness: fitness ?? this.fitness,
        company: company ?? this.company,
        gear: gear ?? this.gear,
        health: health ?? this.health,
        healthVisibleToRescuers: healthVisibleToRescuers ?? this.healthVisibleToRescuers,
        contacts: contacts ?? this.contacts,
      );

  Map<String, dynamic> toJson() => {
        'introSeen': introSeen,
        'registered': registered,
        'name': name,
        'email': email,
        'phone': phone,
        'ageGroup': ageGroup,
        'experience': experience?.name,
        'maxAltitude': maxAltitude,
        'fitness': fitness,
        'company': company?.name,
        'gear': gear.toList(),
        'health': health.toList(),
        'healthVisible': healthVisibleToRescuers,
        'contacts': contacts.map((c) => c.toJson()).toList(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        introSeen: j['introSeen'] == true,
        registered: j['registered'] == true,
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        phone: j['phone'] ?? '',
        ageGroup: j['ageGroup'] ?? '',
        experience: Experience.values.where((e) => e.name == j['experience']).firstOrNone,
        maxAltitude: j['maxAltitude'] ?? -1,
        fitness: j['fitness'] ?? 1,
        company: Company.values.where((e) => e.name == j['company']).firstOrNone,
        gear: {...(j['gear'] as List? ?? const []).cast<String>()},
        health: {...(j['health'] as List? ?? const []).cast<String>()},
        healthVisibleToRescuers: j['healthVisible'] == true,
        contacts: (j['contacts'] as List? ?? const [])
            .map((e) => EmergencyContact.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

// ─────────────────────────── Маршрут ───────────────────────────

class SourceRef {
  final String title;
  final String url;
  const SourceRef(this.title, this.url);
}

class RoutePoint {
  final String name;
  final String role; // start | waypoint | top
  final double lat;
  final double lon;
  const RoutePoint(this.name, this.role, this.lat, this.lon);
}

class RouteInfo {
  final String id;
  final String name;
  final String subtitle;
  final int difficulty; // 1..5
  final int minExperience; // индекс Experience
  final double hoursMin;
  final double hoursMax;
  final int? maxEleM;
  final double? lengthKm;
  final bool exposedRidge;
  final String access; // open | restricted | closed | unverified
  final String? accessVerifiedAt;
  final bool verified;
  final List<RoutePoint> points;
  final String howToGet;
  final List<String> risks;
  final String feeNote;
  final List<SourceRef> sources;

  const RouteInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.difficulty,
    required this.minExperience,
    required this.hoursMin,
    required this.hoursMax,
    required this.maxEleM,
    required this.lengthKm,
    required this.exposedRidge,
    required this.access,
    required this.accessVerifiedAt,
    required this.verified,
    required this.points,
    required this.howToGet,
    required this.risks,
    required this.feeNote,
    required this.sources,
  });

  /// Предлагать для похода можно только проверенные и открытые маршруты.
  bool get plannable => verified && access == 'open' && start != null && top != null;

  RoutePoint? get start => points.where((p) => p.role == 'start').firstOrNone;
  RoutePoint? get top => points.where((p) => p.role == 'top').firstOrNone;

  String get difficultyTitle => switch (difficulty) {
        1 => 'Очень легко',
        2 => 'Легко',
        3 => 'Средне',
        4 => 'Сложно',
        _ => 'Очень сложно',
      };

  String get hoursText =>
      hoursMin == hoursMax ? '${_fmt(hoursMin)} ч' : '${_fmt(hoursMin)}–${_fmt(hoursMax)} ч';

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        id: j['id'],
        name: j['name'],
        subtitle: j['subtitle'] ?? '',
        difficulty: j['difficulty'] ?? 3,
        minExperience: j['min_experience'] ?? 0,
        hoursMin: (j['hours_min'] as num).toDouble(),
        hoursMax: (j['hours_max'] as num).toDouble(),
        maxEleM: j['max_ele_m'],
        lengthKm: (j['length_km'] as num?)?.toDouble(),
        exposedRidge: j['exposed_ridge'] == true,
        access: j['access'] ?? 'unverified',
        accessVerifiedAt: j['access_verified_at'],
        verified: j['verified'] == true,
        points: (j['points'] as List? ?? const [])
            .map((p) => RoutePoint(p['name'], p['role'], (p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))
            .toList(),
        howToGet: j['how_to_get'] ?? '',
        risks: (j['risks'] as List? ?? const []).cast<String>(),
        feeNote: j['fee_note'] ?? '',
        sources: (j['sources'] as List? ?? const []).map((s) => SourceRef(s['title'], s['url'])).toList(),
      );
}

// ─────────────────────────── Погода ───────────────────────────

class HourWeather {
  final DateTime time; // часы Алматы
  final double tempC;
  final double precipMm;
  final int code;
  final double gustKmh;
  final double cape;
  const HourWeather(this.time, this.tempC, this.precipMm, this.code, this.gustKmh, this.cape);

  bool get thunder => code >= 95 || cape >= 1000;
  bool get strongWind => gustKmh >= 50;
  bool get freezing => tempC <= 0;
  bool get rain => precipMm >= 1;
}

enum DayVerdict { good, caution, bad, unknown }

class DayWeather {
  final DateTime date;
  final int code;
  final double tMin;
  final double tMax;
  final double precipSum;
  final double gustMax;
  final DateTime sunrise;
  final DateTime sunset;
  final List<HourWeather> hours; // для верхней точки маршрута
  final bool typical; // true — это не прогноз, а средние данные прошлых лет
  final List<String> warnings;
  final DayVerdict verdict;

  /// Самое раннее начало грозы на любой из высот маршрута (если известно).
  final DateTime? thunderAt;

  const DayWeather({
    required this.date,
    required this.code,
    required this.tMin,
    required this.tMax,
    required this.precipSum,
    required this.gustMax,
    required this.sunrise,
    required this.sunset,
    required this.hours,
    required this.typical,
    required this.warnings,
    required this.verdict,
    this.thunderAt,
  });

  /// Первый час с грозой в светлое время — от него считаем дедлайн.
  DateTime? get firstThunder =>
      thunderAt ??
      hours.where((h) => h.thunder && h.time.hour >= 8 && h.time.hour <= 20).map((h) => h.time).firstOrNone;

  DayWeather copyWith({List<String>? warnings, DayVerdict? verdict, DateTime? thunderAt}) => DayWeather(
        date: date,
        code: code,
        tMin: tMin,
        tMax: tMax,
        precipSum: precipSum,
        gustMax: gustMax,
        sunrise: sunrise,
        sunset: sunset,
        hours: hours,
        typical: typical,
        warnings: warnings ?? this.warnings,
        verdict: verdict ?? this.verdict,
        thunderAt: thunderAt ?? this.thunderAt,
      );
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Прогноз для одной высоты маршрута: старт, середина или верх.
class LevelForecast {
  final String label; // Старт | Середина | Верх
  final String pointName;
  final double elevation; // высота точки по модели рельефа Open-Meteo, м
  final List<DayWeather> days;
  const LevelForecast(this.label, this.pointName, this.elevation, this.days);

  DayWeather? day(DateTime d) => days.where((x) => sameDay(x.date, d)).firstOrNone;
}

class WeatherReport {
  final String routeId;
  final DateTime fetchedAt;
  final List<LevelForecast> levels; // снизу вверх, последний — верх
  final bool fromCache;
  final List<DayWeather> days; // итог по дню: худший вердикт среди высот

  WeatherReport(this.routeId, this.fetchedAt, this.levels, {this.fromCache = false}) : days = _combine(levels);

  LevelForecast get top => levels.last;

  DayWeather? day(DateTime d) => days.where((x) => sameDay(x.date, d)).firstOrNone;

  static List<DayWeather> _combine(List<LevelForecast> levels) {
    if (levels.isEmpty) return const [];
    final top = levels.last;
    return [
      for (final d in top.days)
        () {
          var verdict = d.verdict;
          DateTime? thunder = d.firstThunder;
          final warnings = <String>[...d.warnings];
          for (final l in levels.take(levels.length - 1)) {
            final ld = l.day(d.date);
            if (ld == null) continue;
            if (ld.verdict.index > verdict.index && ld.verdict != DayVerdict.unknown) verdict = ld.verdict;
            final t = ld.firstThunder;
            if (t != null && (thunder == null || t.isBefore(thunder))) thunder = t;
            for (final w in ld.warnings) {
              if (!warnings.contains(w)) warnings.add('${l.label}: $w');
            }
          }
          return d.copyWith(verdict: verdict, warnings: warnings, thunderAt: thunder);
        }(),
    ];
  }
}

// ─────────────────────────── План и поход ───────────────────────────

class TimelineItem {
  final DateTime time;
  final String title;
  final String? note;
  final bool key;
  const TimelineItem(this.time, this.title, {this.note, this.key = false});
}

class DayPlan {
  final String routeId;
  final String routeName;
  final DateTime date;
  final DateTime start;
  final DateTime turnaround;
  final DateTime returnBy;
  final DateTime sunset;
  final String limitingFactor;
  final bool feasible;
  final List<TimelineItem> timeline;
  final List<String> notes;

  const DayPlan({
    required this.routeId,
    required this.routeName,
    required this.date,
    required this.start,
    required this.turnaround,
    required this.returnBy,
    required this.sunset,
    required this.limitingFactor,
    required this.feasible,
    required this.timeline,
    required this.notes,
  });
}

class ChecklistItem {
  final String id;
  final String group; // Одежда | Вода и еда | Безопасность | Документы и деньги
  final String title;
  final String why;
  final bool critical;
  final bool owned; // есть в снаряжении пользователя
  const ChecklistItem(this.id, this.group, this.title, this.why, {this.critical = false, this.owned = true});

  Map<String, dynamic> toJson() =>
      {'id': id, 'group': group, 'title': title, 'why': why, 'critical': critical, 'owned': owned};
  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
      j['id'], j['group'], j['title'], j['why'],
      critical: j['critical'] == true, owned: j['owned'] != false);
}

class Trip {
  final String id;
  final String routeId;
  final String routeName;
  final DateTime date;
  final DateTime start;
  final DateTime turnaround;
  final DateTime returnBy;
  final List<ChecklistItem> checklist;
  final Set<String> packed;
  final bool dchsNotified;

  const Trip({
    required this.id,
    required this.routeId,
    required this.routeName,
    required this.date,
    required this.start,
    required this.turnaround,
    required this.returnBy,
    required this.checklist,
    this.packed = const {},
    this.dchsNotified = false,
  });

  int get criticalLeft => checklist.where((i) => i.critical && !packed.contains(i.id)).length;
  double get packedShare => checklist.isEmpty ? 0 : packed.length / checklist.length;

  Trip copyWith({Set<String>? packed, bool? dchsNotified}) => Trip(
        id: id,
        routeId: routeId,
        routeName: routeName,
        date: date,
        start: start,
        turnaround: turnaround,
        returnBy: returnBy,
        checklist: checklist,
        packed: packed ?? this.packed,
        dchsNotified: dchsNotified ?? this.dchsNotified,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'routeId': routeId,
        'routeName': routeName,
        'date': date.toIso8601String(),
        'start': start.toIso8601String(),
        'turnaround': turnaround.toIso8601String(),
        'returnBy': returnBy.toIso8601String(),
        'checklist': checklist.map((c) => c.toJson()).toList(),
        'packed': packed.toList(),
        'dchs': dchsNotified,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'],
        routeId: j['routeId'],
        routeName: j['routeName'],
        date: DateTime.parse(j['date']),
        start: DateTime.parse(j['start']),
        turnaround: DateTime.parse(j['turnaround']),
        returnBy: DateTime.parse(j['returnBy']),
        checklist: (j['checklist'] as List).map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        packed: {...(j['packed'] as List? ?? const []).cast<String>()},
        dchsNotified: j['dchs'] == true,
      );
}
