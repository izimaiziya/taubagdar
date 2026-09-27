import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../alan/alan_mood.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/iter.dart';
import '../../data/hike.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../data/trip_package.dart';
import '../../data/weather_service.dart';
import '../../ui/trip_widgets.dart';
import '../../ui/widgets.dart';

/// Уровень сигнала: всё хорошо / внимание / опасно.
enum Level { ok, warn, danger }

class _Signal {
  final String key;
  final Level level;
  final String text;
  const _Signal(this.key, this.level, this.text);
}

class _Alert {
  final DateTime at;
  final Level level;
  final String text;
  const _Alert(this.at, this.level, this.text);
}

class HikeScreen extends ConsumerStatefulWidget {
  const HikeScreen({super.key, required this.tripId});
  final String tripId;
  @override
  ConsumerState<HikeScreen> createState() => _HikeScreenState();
}

class _HikeScreenState extends ConsumerState<HikeScreen> {
  Position? _pos;
  int? _battery;
  DateTime _now = almatyNow();
  DateTime? _lastBeat;
  StreamSubscription<Position>? _gps;
  Timer? _tick;
  final _alerts = <_Alert>[];
  final _seen = <String, Level>{};

  @override
  void initState() {
    super.initState();
    _startGps();
    _refreshBattery();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      _now = almatyNow();
      if (_now.minute % 2 == 0) _refreshBattery();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _gps?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _pos = p);
        _heartbeat();
      }, onError: (_) {});
    } catch (_) {/* GPS недоступен — статус покажет это */}
  }

  Future<void> _refreshBattery() async {
    final b = await Battery.level();
    if (mounted && b != null) setState(() => _battery = b);
  }

  /// Последняя точка на сервер раз в 10 минут — если есть связь. Без связи просто пропускаем.
  void _heartbeat() {
    final now = DateTime.now();
    if (_lastBeat != null && now.difference(_lastBeat!).inMinutes < 10) return;
    _lastBeat = now;
    final p = _pos;
    LiveSync.heartbeat(widget.tripId, lat: p?.latitude, lon: p?.longitude, acc: p?.accuracy, battery: _battery);
  }

  // ───────────── правила мониторинга: всё считается на телефоне ─────────────

  List<_Signal> _signals(Trip trip, ActiveHike hike, WeatherReport? wx) {
    final s = <_Signal>[];
    final now = _now;
    final toTurn = trip.turnaround.difference(now);

    if (toTurn.isNegative) {
      s.add(const _Signal('turn', Level.danger, 'Время разворота прошло. Разворачивайся и спускайся той же тропой.'));
    } else if (toTurn.inMinutes <= 30) {
      s.add(_Signal('turn30', Level.warn, 'Через ${toTurn.inMinutes} мин разворот. Где бы ты ни был — пора вниз.'));
    }

    final day = wx?.day(trip.date);
    if (day != null) {
      final toSunset = day.sunset.difference(now);
      if (toSunset.inMinutes <= 60 && !toSunset.isNegative) {
        s.add(_Signal('sunset', Level.danger, 'До заката ${toSunset.inMinutes} мин. Достань фонарь и спускайся.'));
      } else if (toSunset.isNegative) {
        s.add(const _Signal('dark', Level.danger, 'Уже темно. Иди медленно с фонарём, держись тропы.'));
      }
      // Погода на ближайшие 2 часа на всех высотах
      for (final l in wx!.levels) {
        final next = (l.day(trip.date)?.hours ?? const <HourWeather>[])
            .where((h) => !h.time.isBefore(now.subtract(const Duration(minutes: 59))) && h.time.isBefore(now.add(const Duration(hours: 2))))
            .toList();
        final storm = next.where((h) => h.thunder).firstOrNone;
        if (storm != null) {
          final soon = storm.time.difference(now).inMinutes <= 60;
          s.add(_Signal('storm-${l.label}', soon ? Level.danger : Level.warn,
              '${l.label}: возможна гроза около ${hhmm(storm.time)}. Уйди с гребня и открытых мест.'));
        }
        final wind = next.where((h) => h.gustKmh >= 50).firstOrNone;
        if (wind != null) {
          s.add(_Signal('wind-${l.label}', Level.warn, '${l.label}: порывы до ${wind.gustKmh.round()} км/ч около ${hhmm(wind.time)}.'));
        }
        final rain = next.where((h) => h.rain).firstOrNone;
        if (rain != null) {
          s.add(_Signal('rain-${l.label}', Level.warn, '${l.label}: осадки около ${hhmm(rain.time)}. Надень дождевик заранее.'));
        }
        final frost = next.where((h) => h.freezing).firstOrNone;
        if (frost != null) {
          s.add(_Signal('frost-${l.label}', Level.warn, '${l.label}: мороз ${tempText(frost.tempC)}. Возможен лёд на тропе.'));
        }
      }
    } else {
      s.add(const _Signal('nowx', Level.warn, 'Нет прогноза на сегодня. Скачай пакет похода, пока есть связь.'));
    }

    final b = _battery;
    if (b != null && b <= 15) {
      s.add(_Signal('bat15', Level.danger, 'Заряд $b%. Включи энергосбережение и подключи пауэрбанк.'));
    } else if (b != null && b <= 30) {
      s.add(_Signal('bat30', Level.warn, 'Заряд $b%. Береги батарею: закрой лишние приложения.'));
    }

    final p = _pos;
    if (p == null) {
      s.add(const _Signal('gps', Level.warn, 'Ищу спутники. Выйди на открытое место.'));
    } else if (p.accuracy > 50) {
      s.add(_Signal('gpsacc', Level.warn, 'Слабый GPS: точность ±${p.accuracy.round()} м.'));
    }

    final toControl = hike.controlAt.difference(now);
    if (toControl.inMinutes <= 30) {
      s.add(_Signal('control', Level.warn,
          toControl.isNegative ? 'Контрольное время прошло — близким уже может уйти тревога. Отметься!' : 'Через ${toControl.inMinutes} мин контрольное время. Отметься «Я дома» или продли.'));
    }
    return s;
  }

  /// Новое или усилившееся предупреждение — в ленту, с вибрацией и звуком.
  void _collectAlerts(List<_Signal> signals) {
    var added = false;
    for (final sig in signals) {
      final prev = _seen[sig.key];
      if (prev == null || sig.level.index > prev.index) {
        _alerts.insert(0, _Alert(almatyNow(), sig.level, sig.text));
        added = true;
        if (sig.level == Level.danger) {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        } else {
          HapticFeedback.mediumImpact();
        }
      }
      _seen[sig.key] = sig.level;
    }
    if (added && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripsProvider).where((t) => t.id == widget.tripId).firstOrNone;
    final hike = ref.watch(hikeProvider);
    final routes = ref.watch(routesProvider).value ?? const <RouteInfo>[];
    if (trip == null || hike == null || hike.tripId != trip.id) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Поход не начат')));
    }
    final route = routes.where((r) => r.id == trip.routeId).firstOrNone;
    final pkg = ref.watch(packagesProvider)[trip.id];
    WeatherReport? wx;
    if (route != null) {
      wx = pkg != null
          ? ref.read(packagesProvider.notifier).forecastFrom(pkg, route)
          : ref.read(weatherServiceProvider).savedFor(route);
    }

    final signals = _signals(trip, hike, wx);
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectAlerts(signals));
    final level = signals.fold<Level>(Level.ok, (a, s) => s.level.index > a.index ? s.level : a);
    final head = signals.where((s) => s.level == level).firstOrNone;
    final color = switch (level) { Level.ok => Tb.safe, Level.warn => Tb.caution, Level.danger => Tb.danger };
    final t = Theme.of(context).textTheme;
    final toTurn = trip.turnaround.difference(_now);
    final day = wx?.day(trip.date);

    return Scaffold(
      body: Column(children: [
        // Статус-полоса безопасности
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: color,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 14),
          child: Row(children: [
            AlanAvatar(
                mood: switch (level) { Level.ok => MascotMood.calm, Level.warn => MascotMood.worried, Level.danger => MascotMood.alarmed },
                size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(switch (level) { Level.ok => 'Всё в порядке', Level.warn => 'Внимание', Level.danger => 'Опасно' },
                    style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
                Text(head?.text ?? '${trip.routeName}. Иди в своём темпе.',
                    style: const TextStyle(fontFamily: Tb.body, fontSize: 14.5, color: Colors.white, height: 1.3)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            // Время
            Sheet(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(toTurn.isNegative ? 'Разворот был в ${hhmm(trip.turnaround)}' : 'До разворота', style: t.bodySmall),
                Text(toTurn.isNegative ? 'Пора вниз' : _dur(toTurn),
                    style: TextStyle(
                        fontFamily: Tb.display,
                        fontWeight: FontWeight.w800,
                        fontSize: 40,
                        color: toTurn.isNegative ? Tb.danger : Tb.night)),
                const SizedBox(height: 8),
                Wrap(spacing: 20, runSpacing: 8, children: [
                  if (day != null) Stat(hhmm(day.sunset), 'закат, через ${_dur(day.sunset.difference(_now))}'),
                  Stat(hhmm(trip.returnBy), 'расчётное возвращение'),
                  Stat(hhmm(hike.controlAt), 'контрольное время'),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            // Датчики
            Row(children: [
              Expanded(
                child: _Tile(
                  icon: Icons.my_location_rounded,
                  title: _pos == null ? 'GPS: поиск' : '±${_pos!.accuracy.round()} м',
                  sub: _pos == null ? 'Нужно открытое небо' : '${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}',
                  bad: _pos == null || _pos!.accuracy > 50,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.battery_std_rounded,
                  title: _battery == null ? 'Заряд —' : 'Заряд $_battery%',
                  sub: _pos != null && _pos!.altitude != 0 ? 'Высота ~${_pos!.altitude.round()} м' : 'Высота —',
                  bad: (_battery ?? 100) <= 30,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _Tile(
              icon: Env.hasSupabase ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
              title: Env.hasSupabase ? 'Тревога включена на сервере' : 'Тревога только на телефоне',
              sub: Env.hasSupabase
                  ? 'Если не отметишься до ${hhmm(hike.controlAt)}, близкие получат последнюю точку, даже если телефон сядет'
                  : 'Сервер не подключён: при разряде телефона близкие не узнают. Предупреди их сам',
              bad: !Env.hasSupabase,
            ),
            if (wx != null) ...[
              const SectionTitle('Погода на трёх высотах'),
              Sheet(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LevelsTable(report: wx, date: trip.date, fromHour: _now.hour.clamp(6, 21)),
                  const SizedBox(height: 8),
                  Text(levelsCaption(wx), style: t.bodySmall),
                ]),
              ),
            ],
            const SectionTitle('Алан предупреждает'),
            if (_alerts.isEmpty)
              const AlanSays('Пока всё спокойно. Я слежу за временем, погодой и зарядом.', mood: MascotMood.calm, avatar: 48)
            else
              for (final a in _alerts.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 48, child: Text(hhmm(a.at), style: t.labelMedium)),
                    Icon(a.level == Level.danger ? Icons.error_rounded : Icons.warning_amber_rounded,
                        size: 18, color: a.level == Level.danger ? Tb.danger : Tb.caution),
                    const SizedBox(width: 6),
                    Expanded(child: Text(a.text, style: t.bodyMedium)),
                  ]),
                ),
          ]),
        ),
        // Действия
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TbButton('SOS', color: Tb.danger, icon: Icons.sos_rounded, onPressed: () => context.push('/sos')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TbButton('Я дома', icon: Icons.home_rounded, onPressed: () => _finish(context)),
                ),
              ]),
              TbTextButton('Продлить контрольное время на 1 час', onPressed: () async {
                await ref.read(hikeProvider.notifier).extend(const Duration(hours: 1));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Контрольное время продлено на 1 час')));
                }
              }),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _finish(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ты дома?'),
        content: const Text('Я выключу слежение и отменю тревогу для близких.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ещё нет')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Да, я дома')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hikeProvider.notifier).finish();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('С возвращением! Поход завершён.')));
      context.go('/app');
    }
  }

  static String _dur(Duration d) {
    if (d.isNegative) return '0 мин';
    final h = d.inHours, m = d.inMinutes % 60;
    return h == 0 ? '$m мин' : '$h ч $m мин';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.sub, this.bad = false});
  final IconData icon;
  final String title;
  final String sub;
  final bool bad;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tb.snow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: bad ? Tb.caution : Tb.mist, width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: bad ? Tb.caution : Tb.sky),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15)),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      );
}
