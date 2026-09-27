import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/env.dart';
import 'hike.dart';
import 'models.dart';

/// Переопределяется в main() готовым экземпляром.
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

// ─────────────────────────── Профиль ───────────────────────────

class ProfileNotifier extends Notifier<UserProfile> {
  static const _key = 'profile.v1';

  @override
  UserProfile build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return const UserProfile();
    }
  }

  void edit(UserProfile Function(UserProfile p) change) {
    state = change(state);
    ref.read(prefsProvider).setString(_key, jsonEncode(state.toJson()));
  }

  /// Облачная копия профиля (если подключён Supabase). Ошибка сети не мешает работе.
  Future<void> pushToCloud() async {
    if (!Env.hasSupabase) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await client.from('profiles').upsert({'id': uid, 'data': state.toJson()});
    } catch (_) {/* повторим при следующем изменении */}
    await LiveSync.linkContacts(state);
  }

  /// Отмечает контакты, которые подключились к Telegram-боту.
  Future<void> refreshLinks() async {
    final linked = await LiveSync.linkedTokens();
    if (linked.isEmpty) return;
    edit((p) => p.copyWith(contacts: [
          for (final c in p.contacts)
            EmergencyContact(
              name: c.name,
              relation: c.relation,
              phone: c.phone,
              inviteToken: c.inviteToken,
              verified: c.verified || linked.contains(c.inviteToken),
            )
        ]));
  }

  Future<bool> pullFromCloud() async {
    if (!Env.hasSupabase) return false;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final row = await client.from('profiles').select('data').eq('id', uid).maybeSingle();
      if (row == null) return false;
      final p = UserProfile.fromJson(Map<String, dynamic>.from(row['data']));
      edit((_) => p.copyWith(introSeen: true));
      return p.registered;
    } catch (_) {
      return false;
    }
  }

  void resetAll() {
    ref.read(prefsProvider).remove(_key);
    state = const UserProfile();
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// ─────────────────────────── Маршруты ───────────────────────────

final routesProvider = FutureProvider<List<RouteInfo>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/routes.json');
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return (j['routes'] as List).map((e) => RouteInfo.fromJson(Map<String, dynamic>.from(e))).toList();
});

// ─────────────────────────── Походы ───────────────────────────

class TripsNotifier extends Notifier<List<Trip>> {
  static const _key = 'trips.v1';

  @override
  List<Trip> build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => Trip.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return const [];
    }
  }

  void _save() => ref.read(prefsProvider).setString(_key, jsonEncode(state.map((t) => t.toJson()).toList()));

  void add(Trip t) {
    state = [...state.where((x) => x.id != t.id), t]..sort((a, b) => a.date.compareTo(b.date));
    _save();
  }

  void togglePacked(String tripId, String itemId) {
    state = [
      for (final t in state)
        if (t.id == tripId)
          t.copyWith(packed: t.packed.contains(itemId) ? ({...t.packed}..remove(itemId)) : {...t.packed, itemId})
        else
          t
    ];
    _save();
  }

  /// Обновить время плана по свежему прогнозу (при скачивании пакета).
  void updatePlan(String tripId, DayPlan p) {
    state = [
      for (final t in state)
        if (t.id == tripId)
          Trip(
            id: t.id,
            routeId: t.routeId,
            routeName: t.routeName,
            date: t.date,
            start: p.start,
            turnaround: p.turnaround,
            returnBy: p.returnBy,
            checklist: t.checklist,
            packed: t.packed,
            dchsNotified: t.dchsNotified,
          )
        else
          t
    ];
    _save();
  }

  void setNotified(String tripId, bool v) {
    state = [for (final t in state) t.id == tripId ? t.copyWith(dchsNotified: v) : t];
    _save();
  }

  void remove(String tripId) {
    state = state.where((t) => t.id != tripId).toList();
    _save();
  }
}

final tripsProvider = NotifierProvider<TripsNotifier, List<Trip>>(TripsNotifier.new);

/// Ближайший предстоящий поход.
final nextTripProvider = Provider<Trip?>((ref) {
  final today = almatyToday();
  final upcoming = ref.watch(tripsProvider).where((t) => !t.date.isBefore(today)).toList();
  return upcoming.isEmpty ? null : upcoming.first;
});
