import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import '../widgets/stories_rail.dart';
import '../widgets/theme_scene.dart';
import 'new_chat_screen.dart';
import 'join_group_screen.dart';
import 'discover_groups_screen.dart';
import 'settings_screen.dart';
import 'thread_screen.dart';
import 'user_profile_screen.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatController>().start();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final auth = context.watch<AuthController>();
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;
    final scenic = theme.isFunTheme;
    final filters = chat.incomingRequestCount > 0
        ? [
            ('all', 'All'),
            ('friends', 'Friends'),
            ('unread', 'Unread'),
            ('groups', 'Groups'),
            ('archived', 'Archived'),
          ]
        : [
            ('all', 'All'),
            ('unread', 'Unread'),
            ('groups', 'Groups'),
            ('friends', 'Friends'),
            ('archived', 'Archived'),
          ];

    return Scaffold(
      backgroundColor: scenic ? Colors.transparent : colors.body,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: scenic ? colors.surface.withValues(alpha: 0.58) : colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QuantumChat'),
            Text(
              auth.user?.title ?? '',
              style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen())),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: 'Discover groups',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverGroupsScreen())),
            icon: const Icon(Icons.travel_explore_outlined),
          ),
          IconButton(
            tooltip: 'Join group',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinGroupScreen())),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
            icon: const Icon(Icons.group_add_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ThemeScene(
        themeId: theme.id,
        intensity: 0.72,
        child: Column(
          children: [
          if (auth.user?.emailVerified == false)
            Material(
              color: colors.accentMuted,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text('Verify your email', style: TextStyle(color: colors.textPrimary))),
                    TextButton(
                      onPressed: () async {
                        try {
                          await auth.api.resendVerification();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Verification email sent')),
                            );
                          }
                        } catch (_) {}
                      },
                      child: const Text('Resend'),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: search,
              onChanged: (v) => chat.searchPeople(v),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          search.clear();
                          chat.searchPeople('');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: filters.map((f) {
                final selected = chat.filter == f.$1;
                final requestCount = f.$1 == 'friends' ? chat.incomingRequestCount : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Badge(
                    isLabelVisible: requestCount > 0,
                    label: Text(requestCount > 9 ? '9+' : '$requestCount'),
                    backgroundColor: const Color(0xFFE11D48),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: selected,
                      onSelected: (_) => chat.setFilter(f.$1),
                      selectedColor: colors.accent,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: requestCount > 0 && !selected
                          ? const Color(0x33E11D48)
                          : colors.elevated,
                      side: BorderSide(
                        color: requestCount > 0 && !selected
                            ? const Color(0xFFE11D48)
                            : (selected ? colors.accent : colors.border),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const StoriesRail(),
          if (chat.filter == 'friends' && chat.friendRequests.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Friend requests',
                    style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800),
                  ),
                ),
                ...chat.friendRequests.map(
                  (r) => ListTile(
                    leading: UserAvatar(name: r.from.title, userId: r.from.id, hasAvatar: r.from.hasAvatar),
                    title: Text(r.from.title, style: TextStyle(color: colors.textPrimary)),
                    subtitle: Text('@${r.from.username}', style: TextStyle(color: colors.textMuted)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Accept',
                          onPressed: () => chat.acceptFriendRequest(r.id),
                          icon: Icon(Icons.check_circle, color: colors.success),
                        ),
                        IconButton(
                          tooltip: 'Decline',
                          onPressed: () => chat.declineFriendRequest(r.id),
                          icon: Icon(Icons.cancel, color: colors.error),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(color: colors.border.withValues(alpha: 0.5)),
              ],
            ),
          const SizedBox(height: 4),
          Expanded(
            child: chat.loadingInbox && chat.conversations.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: chat.refreshInbox,
                    child: chat.conversations.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              Icon(Icons.chat_bubble_outline, size: 48, color: colors.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                'No conversations yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: chat.conversations.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: colors.border.withValues(alpha: scenic ? 0.35 : 0.6),
                            ),
                            itemBuilder: (context, i) {
                              final c = chat.conversations[i];
                              return Material(
                                color: scenic ? colors.surface.withValues(alpha: 0.28) : Colors.transparent,
                                child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: GestureDetector(
                                  onTap: c.type == ConversationType.dm && !c.isSelfChat
                                      ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: c.id)))
                                      : null,
                                  child: UserAvatar(
                                    name: c.title,
                                    userId: c.id,
                                    hasAvatar: c.peer?.hasAvatar == true || c.group?.hasPhoto == true,
                                    isGroup: c.type == ConversationType.group,
                                    online: c.online,
                                    size: 48,
                                  ),
                                ),
                                title: Text(
                                  c.title,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: c.unread ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  (c.peer?.statusText.isNotEmpty == true ? c.peer!.statusText : null) ??
                                      c.subtitle ??
                                      (c.online
                                          ? 'online'
                                          : formatLastSeen(c.peer?.lastLoginAt, online: c.online)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.unread ? colors.accentCyan : colors.textMuted),
                                ),
                                trailing: c.unread
                                    ? Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                                      )
                                    : null,
                                onTap: () async {
                                  await chat.open(c);
                                  if (context.mounted) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ThreadScreen()),
                                    );
                                    chat.closeThread();
                                  }
                                },
                              ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
