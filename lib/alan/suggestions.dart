import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/env.dart';
import '../data/models.dart';
import '../data/stores.dart';
import '../data/trip_package.dart';
import 'alan_mood.dart';

enum SuggestionAction { openContacts, openTrip, openChat, openRoutes, openSafety }

class AlanSuggestion {
  final int priority; // 100 — критично
  final String title;
  final String body;
  final String cta;
  final IconData icon;
  final SuggestionAction action;
  final String? payload; // id похода или текст для чата
  final MascotMood mood;

  const AlanSuggestion({
    required this.priority,
    required this.title,
    required this.body,
    required this.cta,
    required this.icon,
    required this.action,
    this.payload,
    this.mood = MascotMood.happy,
  });
}

/// Подсказки строятся правилами на телефоне: работают без интернета
/// и всегда опираются на реальное состояние приложения.
final suggestionsProvider = Provider<List<AlanSuggestion>>((ref) {
  final p = ref.watch(profileProvider);
  final trip = ref.watch(nextTripProvider);
  final today = almatyToday();
  final now = almatyNow();
  final out = <AlanSuggestion>[];

  if (p.contacts.isEmpty) {
    out.add(const AlanSuggestion(
      priority: 100,
      title: 'Кто узнает, если ты не вернёшься?',
      body: 'Добавь близкого человека — я напишу ему, если ты не отметишься вовремя.',
      cta: 'Добавить контакт',
      icon: Icons.favorite_rounded,
      action: SuggestionAction.openContacts,
      mood: MascotMood.worried,
    ));
  }

  if (trip != null) {
    final days = trip.date.difference(today).inDays;
    final when = days == 0 ? 'сегодня' : days == 1 ? 'завтра' : 'через $days дн.';
    if (trip.criticalLeft > 0 && days <= 2) {
      out.add(AlanSuggestion(
        priority: 90,
        title: 'Рюкзак ещё не собран',
        body: 'Поход на ${trip.routeName} $when, осталось ${trip.criticalLeft} важных вещей.',
        cta: 'Открыть список',
        icon: Icons.backpack_rounded,
        action: SuggestionAction.openTrip,
        payload: trip.id,
        mood: MascotMood.worried,
      ));
    }
    if (ref.watch(packagesProvider)[trip.id] == null && days <= 2) {
      out.add(AlanSuggestion(
        priority: 88,
        title: 'Скачай пакет похода',
        body: 'Прогноз на трёх высотах и план будут работать в горах без связи.',
        cta: 'Скачать',
        icon: Icons.download_rounded,
        action: SuggestionAction.openTrip,
        payload: trip.id,
      ));
    }
    if (!trip.dchsNotified && days <= 2) {
      out.add(AlanSuggestion(
        priority: 85,
        title: 'Сообщи ДЧС о походе',
        body: 'Это обязательное правило для туристов. Текст уведомления я уже подготовил.',
        cta: 'Посмотреть текст',
        icon: Icons.assignment_turned_in_rounded,
        action: SuggestionAction.openTrip,
        payload: trip.id,
      ));
    }
    if (days == 1 && now.hour >= 18) {
      out.add(AlanSuggestion(
        priority: 80,
        title: 'Вечер перед походом',
        body: 'Поставь телефон и пауэрбанк на зарядку, проверь прогноз и ложись пораньше. Выезд в ${_hhmm(trip.start.subtract(const Duration(hours: 1)))}.',
        cta: 'Проверить погоду',
        icon: Icons.nights_stay_rounded,
        action: SuggestionAction.openChat,
        payload: 'Какая погода будет завтра на ${trip.routeName}?',
      ));
    }
    if (days >= 3) {
      out.add(AlanSuggestion(
        priority: 40,
        title: '${trip.routeName} $when',
        body: 'Собрано ${(trip.packedShare * 100).round()}% вещей. Прогноз я обновлю ближе к дате.',
        cta: 'Открыть поход',
        icon: Icons.terrain_rounded,
        action: SuggestionAction.openTrip,
        payload: trip.id,
      ));
    }
  } else {
    out.add(const AlanSuggestion(
      priority: 50,
      title: 'Куда пойдём в выходные?',
      body: 'Подберу маршрут по твоему уровню и проверю погоду наверху.',
      cta: 'Спланировать',
      icon: Icons.explore_rounded,
      action: SuggestionAction.openChat,
      payload: 'Подбери мне маршрут на эту субботу',
      mood: MascotMood.cheering,
    ));
  }

  final month = today.month;
  if (month >= 4 && month <= 7) {
    out.add(const AlanSuggestion(
      priority: 30,
      title: 'Сезон клещей',
      body: 'В предгорьях сейчас клещи. Закрытая светлая одежда и осмотр после похода.',
      cta: 'Что делать',
      icon: Icons.bug_report_rounded,
      action: SuggestionAction.openSafety,
    ));
  }

  if (p.expLevel == 0 && p.company == Company.solo) {
    out.add(const AlanSuggestion(
      priority: 60,
      title: 'Первый поход — вдвоём',
      body: 'Я буду рядом, но в первый раз лучше позвать друга или пойти с гидом.',
      cta: 'Смотреть маршруты',
      icon: Icons.group_rounded,
      action: SuggestionAction.openRoutes,
    ));
  }

  out.sort((a, b) => b.priority.compareTo(a.priority));
  return out;
});

/// Общее настроение Алана на главном экране.
final homeMoodProvider = Provider<MascotMood>((ref) {
  final s = ref.watch(suggestionsProvider);
  if (s.isEmpty) return MascotMood.happy;
  return s.first.priority >= 85 ? MascotMood.worried : s.first.mood;
});

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
