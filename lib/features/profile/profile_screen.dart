import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/send.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../ui/widgets.dart';

const _gearNames = {
  'boots': 'Треккинговые ботинки',
  'poles': 'Палки',
  'shell': 'Мембранная куртка',
  'headlamp': 'Налобный фонарь',
  'powerbank': 'Пауэрбанк',
  'firstaid': 'Аптечка',
  'thermos': 'Термос',
};

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final t = Theme.of(context).textTheme;
    void upd(UserProfile Function(UserProfile) f) {
      ref.read(profileProvider.notifier).edit(f);
      ref.read(profileProvider.notifier).pushToCloud();
    }

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
        Row(children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Tb.sky,
            child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                style: const TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 28, color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name.isEmpty ? 'Турист' : p.name, style: t.displaySmall),
              const SizedBox(height: 4),
              Text(p.email.isEmpty ? 'Локальный режим' : p.email, style: t.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        Sheet(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Pill(p.levelTitle, filled: true),
              const Spacer(),
              Text('темп ×${p.paceFactor.toStringAsFixed(2)}', style: t.labelMedium),
            ]),
            const SizedBox(height: 10),
            Text(p.levelHint, style: t.bodyLarge),
          ]),
        ),

        SectionTitle('Экстренные контакты',
            trailing: IconButton.filledTonal(
              onPressed: () => _addContact(context, ref),
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Добавить контакт',
            )),
        if (p.contacts.isEmpty)
          const AlanSays('Добавь хотя бы одного человека. Без этого я не смогу позвать помощь.', avatar: 52)
        else
          Sheet(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(children: [
              for (final c in p.contacts)
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Tb.air, child: Text(c.name.isEmpty ? '?' : c.name[0], style: const TextStyle(color: Tb.skyDeep))),
                  title: Text(c.name, style: t.titleMedium),
                  subtitle: Text('${c.relation.isEmpty ? '' : '${c.relation}, '}${c.phone}', style: t.bodySmall),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'invite') _invite(p, c);
                      if (v == 'remove') upd((x) => x.copyWith(contacts: x.contacts.where((y) => y != c).toList()));
                    },
                    itemBuilder: (_) => [
                      if (Env.telegramBot.isNotEmpty) const PopupMenuItem(value: 'invite', child: Text('Отправить приглашение')),
                      const PopupMenuItem(value: 'remove', child: Text('Удалить')),
                    ],
                  ),
                ),
            ]),
          ),

        const SectionTitle('Снаряжение'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _gearNames.entries)
            FilterChip(
              label: Text(e.value),
              selected: p.gear.contains(e.key),
              showCheckmark: false,
              onSelected: (on) => upd((x) => x.copyWith(gear: on ? {...x.gear, e.key} : ({...x.gear}..remove(e.key)))),
              selectedColor: Tb.sky,
              backgroundColor: Tb.snow,
              labelStyle: TextStyle(
                  fontFamily: Tb.body, fontWeight: FontWeight.w600, color: p.gear.contains(e.key) ? Colors.white : Tb.night),
              side: BorderSide(color: p.gear.contains(e.key) ? Tb.sky : Tb.mist, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            ),
        ]),

        const SectionTitle('О приложении'),
        Sheet(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(children: [
            _Link('Погода: Open-Meteo (CC BY 4.0)', 'https://open-meteo.com/'),
            _Link('Карта: © участники OpenStreetMap', 'https://www.openstreetmap.org/copyright'),
            ListTile(
              title: const Text('Лицензии библиотек и шрифтов'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(context: context, applicationName: 'TauBağdar'),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Выйти и удалить данные с телефона?'),
                content: const Text('Профиль и походы на этом устройстве будут удалены.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
                ],
              ),
            );
            if (ok != true) return;
            if (Env.hasSupabase) {
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {}
            }
            for (final trip in ref.read(tripsProvider)) {
              ref.read(tripsProvider.notifier).remove(trip.id);
            }
            ref.read(profileProvider.notifier).resetAll();
            if (context.mounted) context.go('/intro');
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Tb.danger,
            side: const BorderSide(color: Tb.mist, width: 1.5),
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: const Text('Выйти'),
        ),
      ]),
    );
  }

  void _invite(UserProfile p, EmergencyContact c) {
    shareToTelegram(
      'https://t.me/${Env.telegramBot}?start=${c.inviteToken}',
      '${p.name} добавил(а) тебя экстренным контактом в TauBağdar. Открой ссылку и нажми Start — тогда я смогу написать тебе, если что-то случится в горах.',
    );
  }

  Future<void> _addContact(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final rel = TextEditingController();
    final phone = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tb.ice,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Новый контакт', style: Theme.of(c).textTheme.displaySmall),
          const SizedBox(height: 16),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Имя')),
          const SizedBox(height: 10),
          TextField(controller: rel, decoration: const InputDecoration(hintText: 'Кем приходится')),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: const InputDecoration(hintText: '700 000 00 00', prefixText: '+7 '),
          ),
          const SizedBox(height: 16),
          TbButton('Сохранить', onPressed: () => Navigator.pop(c, true)),
        ]),
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty && phone.text.length == 10) {
      final c = EmergencyContact(
        name: name.text.trim(),
        relation: rel.text.trim(),
        phone: '+7${phone.text}',
        inviteToken: EmergencyContact.newToken(),
      );
      ref.read(profileProvider.notifier).edit((x) => x.copyWith(contacts: [...x.contacts, c]));
      ref.read(profileProvider.notifier).pushToCloud();
      if (Env.telegramBot.isNotEmpty) _invite(ref.read(profileProvider), c);
    }
  }
}

class _Link extends StatelessWidget {
  const _Link(this.title, this.url);
  final String title;
  final String url;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
}
