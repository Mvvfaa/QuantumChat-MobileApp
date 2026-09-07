import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import 'thread_screen.dart';
import 'user_profile_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final query = TextEditingController();
  List<QcUser> results = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    results = context.read<ChatController>().users;
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => loading = true);
    try {
      final users = await context.read<AuthController>().api.listUsers(q: q.trim());
      setState(() => results = users);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chat = context.read<ChatController>();
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: query,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Search by username',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final u = results[i];
                final isFriend = chat.friends.any((f) => f.id == u.id);
                final isMe = u.id == chat.me.id;
                return ListTile(
                  leading: GestureDetector(
                    onTap: isMe ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u.id))),
                    child: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar),
                  ),
                  title: Text(u.title, style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text('@${u.username}', style: TextStyle(color: colors.textMuted)),
                  trailing: isMe || isFriend
                      ? null
                      : IconButton(
                          tooltip: 'Add friend',
                          icon: Icon(Icons.person_add, color: colors.accent),
                          onPressed: () async {
                            try {
                              await context.read<AuthController>().api.sendFriendRequest(u.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Friend request sent')),
                                );
                              }
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                            }
                          },
                        ),
                  onTap: () async {
                    final conv = Conversation(
                      key: chat.storage.conversationKeyForUser(u.id),
                      type: ConversationType.dm,
                      id: u.id,
                      title: u.title,
                      peer: u,
                    );
                    await chat.open(conv);
                    if (context.mounted) {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ThreadScreen()));
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final name = TextEditingController();
  final selected = <String>{};
  bool busy = false;
  String visibility = 'private';
  String joinPolicy = 'open';

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Group name'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visibility', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'private', label: Text('Private'), icon: Icon(Icons.lock_outline, size: 16)),
                    ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(Icons.public, size: 16)),
                  ],
                  selected: {visibility},
                  onSelectionChanged: (s) => setState(() => visibility = s.first),
                ),
                if (visibility == 'public') ...[
                  const SizedBox(height: 12),
                  Text('Join policy', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'open', label: Text('Open')),
                      ButtonSegment(value: 'request', label: Text('Request')),
                    ],
                    selected: {joinPolicy},
                    onSelectionChanged: (s) => setState(() => joinPolicy = s.first),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add members', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: ListView(
              children: chat.users.map((u) {
                final on = selected.contains(u.id);
                return CheckboxListTile(
                  value: on,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selected.add(u.id);
                    } else {
                      selected.remove(u.id);
                    }
                  }),
                  title: Text(u.title, style: TextStyle(color: colors.textPrimary)),
                  secondary: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar, size: 36),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: QcPrimaryButton(
              label: busy ? 'Creating…' : 'Create group',
              loading: busy,
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final group = await chat.createGroup(
                        name.text.trim(),
                        selected.toList(),
                        visibility: visibility,
                        joinPolicy: visibility == 'public' ? joinPolicy : null,
                      );
                      if (group != null && context.mounted) {
                        final conv = Conversation(
                          key: chat.storage.conversationKeyForGroup(group.id),
                          type: ConversationType.group,
                          id: group.id,
                          title: group.name,
                          group: group,
                        );
                        await chat.open(conv);
                        if (context.mounted) {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ThreadScreen()));
                        }
                      } else if (mounted) {
                        setState(() => busy = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}
