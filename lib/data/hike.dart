import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/env.dart';
import 'models.dart';
import 'stores.dart';

// ─────────────────────────── Батарея ───────────────────────────

/// Заряд батареи через небольшой канал в MainActivity.kt (без сторонних плагинов).
/// Если канал не добавлен — возвращает null, и приложение просто не показывает заряд.
class Battery {
  static const _ch = MethodChannel('taubagdar/battery');
  static Future<int?> level() async {
    try {
      return await _ch.invokeMethod<int>('level');
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────── Активный поход ───────────────────────────

class ActiveHike {
  final String tripId;
  final DateTime startedAt;
  final DateTime controlAt; // контрольное время: не отметился — тревога близким
  const ActiveHike(this.tripId, this.startedAt, this.controlAt);

  Map<String, dynamic> toJson() =>
      {'tripId': tripId, 'startedAt': startedAt.toIso8601String(), 'controlAt': controlAt.toIso8601String()};
  factory ActiveHike.fromJson(Map<String, dynamic> j) =>
      ActiveHike(j['tripId'], DateTime.parse(j['startedAt']), DateTime.parse(j['controlAt']));
}

class HikeNotifier extends Notifier<ActiveHike?> {
  static const _key = 'hike.active';

  @override
  ActiveHike? build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return null;
    try {
      return ActiveHike.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Контрольное время = расчётное возвращение + 1 час запаса.
  Future<bool> start(Trip trip) async {
    final h = ActiveHike(trip.id, almatyNow(), trip.returnBy.add(const Duration(hours: 1)));
    state = h;
    ref.read(prefsProvider).setString(_key, jsonEncode(h.toJson()));
    return LiveSync.startTrip(ref.read(profileProvider), trip, h.controlAt);
  }

  Future<void> extend(Duration d) async {
    final h = state;
    if (h == null) return;
    final n = ActiveHike(h.tripId, h.startedAt, h.controlAt.add(d));
    state = n;
    ref.read(prefsProvider).setString(_key, jsonEncode(n.toJson()));
    await LiveSync.extend(h.tripId, n.controlAt);
  }

  Future<void> finish() async {
    final h = state;
    state = null;
    ref.read(prefsProvider).remove(_key);
    if (h != null) await LiveSync.finish(h.tripId);
  }
}

final hikeProvider = NotifierProvider<HikeNotifier, ActiveHike?>(HikeNotifier.new);

// ─────────────────────────── Сервер тревоги (Supabase) ───────────────────────────

/// Всё, что делает тревогу независимой от телефона. Если турист не отметился
/// к контрольному времени, сервер сам пишет близким в Telegram с последней точкой.
/// Без Supabase методы ничего не делают и возвращают false.
class LiveSync {
  static SupabaseClient? get _c => Env.hasSupabase ? Supabase.instance.client : null;
  static String? get _uid => _c?.auth.currentUser?.id;

  /// Время Алматы → абсолютное время для сервера.
  static String _utc(DateTime almaty) =>
      DateTime.utc(almaty.year, almaty.month, almaty.day, almaty.hour, almaty.minute)
          .subtract(const Duration(hours: 5))
          .toIso8601String();

  static Future<bool> _run(Future<void> Function(SupabaseClient c, String uid) f) async {
    final c = _c, uid = _uid;
    if (c == null || uid == null) return false;
    try {
      await f(c, uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> linkContacts(UserProfile p) => _run((c, uid) async {
        if (p.contacts.isEmpty) return;
        await c.from('contact_links').upsert([
          for (final x in p.contacts) {'token': x.inviteToken, 'owner': uid, 'owner_name': p.name, 'name': x.name}
        ], onConflict: 'token', ignoreDuplicates: true);
      });

  /// Токены контактов, которые нажали Start у бота.
  static Future<Set<String>> linkedTokens() async {
    final c = _c, uid = _uid;
    if (c == null || uid == null) return {};
    try {
      final rows = await c.from('contact_links').select('token').eq('owner', uid).not('chat_id', 'is', null);
      return {for (final r in rows) '${r['token']}'};
    } catch (_) {
      return {};
    }
  }

  static Future<bool> startTrip(UserProfile p, Trip t, DateTime controlAt) => _run((c, uid) async {
        await c.from('live_trips').upsert({
          'id': '$uid-${t.id}',
          'owner': uid,
          'owner_name': p.name,
          'owner_phone': p.phone,
          'route_name': t.routeName,
          'control_at': _utc(controlAt),
          'status': 'active',
        });
      });

  static Future<bool> heartbeat(String tripId, {double? lat, double? lon, double? acc, int? battery}) =>
      _run((c, uid) async {
        await c.from('live_trips').update({
          if (lat != null) 'last_lat': lat,
          if (lon != null) 'last_lon': lon,
          if (acc != null) 'last_acc': acc,
          if (battery != null) 'last_battery': battery,
          'last_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', '$uid-$tripId');
      });

  static Future<bool> extend(String tripId, DateTime controlAt) => _run((c, uid) async {
        await c.from('live_trips').update({'control_at': _utc(controlAt), 'status': 'active'}).eq('id', '$uid-$tripId');
      });

  static Future<bool> finish(String tripId) => _run((c, uid) async {
        await c.from('live_trips').update({'status': 'done'}).eq('id', '$uid-$tripId');
      });
}
