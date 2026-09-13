import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';

enum _ActivityFilter { all, friends, chats }

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  _ActivityFilter filter = _ActivityFilter.all;
  List<Map<String, dynamic>> localEvents = [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromController());
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final userId = context.read<AuthController>().user?.id ?? 'anon';
    final raw = prefs.getString('qc_activity_$userId');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => localEvents = list);
    } catch (_) {}
  }

  Future<void> _persist(List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final userId = context.read<AuthController>().user?.id ?? 'anon';
    await prefs.setString('qc_activity_$userId', jsonEncode(events.take(100).toList()));
  }

  Future<void> _syncFromController() async {
    final chat = context.read<ChatController>();
    final events = List<Map<String, dynamic>>.from(localEvents);
    final existingIds = events.map((e) => '${e['id']}').toSet();

    for (final r in chat.friendRequests) {
      final id = 'fr_${r.id}';
      if (existingIds.contains(id)) continue;
      events.insert(0, {
        'id': id,
        'type': 'friend_request',
        'title': 'Friend request from ${r.from.title}',
        'at': (r.createdAt ?? DateTime.now()).toIso8601String(),
      });
    }

    events.insert(0, {
      'id': 'chats_${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
      'type': 'chats',
      'title': '${chat.conversations.length} conversations in inbox',
      'at': DateTime.now().toIso8601String(),
    });

    // Dedupe chat summary entries — keep latest only.
    final deduped = <Map<String, dynamic>>[];
    var sawChats = false;
    for (final e in events) {
      if (e['type'] == 'chats') {
        if (sawChats) continue;
        sawChats = true;
      }
      deduped.add(e);
    }

    await _persist(deduped);
    if (mounted) setState(() => localEvents = deduped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chat = context.watch<ChatController>();

    final items = <Map<String, dynamic>>[
      ...localEvents,
      ...chat.friendRequests.map(
        (r) => {
          'id': 'live_fr_${r.id}',
          'type': 'friend_request',
          'title': 'Pending: ${r.from.title}',
          'at': (r.createdAt ?? DateTime.now()).toIso8601String(),
        },
      ),
    ];

    final filtered = items.where((e) {
      switch (filter) {
        case _ActivityFilter.all:
          return true;
        case _ActivityFilter.friends:
          return e['type'] == 'friend_request';
        case _ActivityFilter.chats:
          return e['type'] == 'chats';
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final entry in const [
                  (_ActivityFilter.all, 'All'),
                  (_ActivityFilter.friends, 'Friends'),
                  (_ActivityFilter.chats, 'Chats'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(entry.$2),
                      selected: filter == entry.$1,
                      onSelected: (_) => setState(() => filter = entry.$1),
                      selectedColor: colors.accent,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No activity yet', style: TextStyle(color: colors.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(color: colors.border.withValues(alpha: 0.4)),
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      final type = '${e['type']}';
                      final icon = type == 'friend_request'
                          ? Icons.person_add_alt_1_outlined
                          : Icons.chat_bubble_outline;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, color: colors.accentCyan),
                        title: Text('${e['title']}', style: TextStyle(color: colors.textPrimary)),
                        subtitle: Text(
                          _fmt(e['at']?.toString()),
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 2) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
