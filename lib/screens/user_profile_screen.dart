import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import 'thread_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  QcUser? user;
  bool loading = true;
  String? error;
  List<HighlightItem> highlights = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final u = await api.getUser(widget.userId);
      List<HighlightItem> hl = [];
      try {
        hl = await api.listHighlights(userId: widget.userId);
      } catch (_) {}
      if (mounted) {
        setState(() {
          user = u;
          highlights = hl;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get _isOwn {
    return context.read<AuthController>().user?.id == widget.userId;
  }

  bool get _isFriend {
    return context.read<ChatController>().friends.any((f) => f.id == widget.userId);
  }

  bool? _blockedOverride;

  bool get _isBlocked {
    if (_blockedOverride != null) return _blockedOverride!;
    final me = context.read<AuthController>().user;
    return me?.blockedUsers.contains(widget.userId) ?? false;
  }

  bool get _isOnline {
    return context.read<ChatController>().onlineUserIds.contains(widget.userId);
  }

  Future<void> _sendMessage() async {
    final chat = context.read<ChatController>();
    final u = user;
    if (u == null) return;
    final conv = Conversation(
      key: chat.storage.conversationKeyForUser(u.id),
      type: ConversationType.dm,
      id: u.id,
      title: u.title,
      peer: u,
    );
    await chat.open(conv);
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ThreadScreen()));
    }
  }

  Future<void> _sendFriendRequest() async {
    try {
      await context.read<AuthController>().api.sendFriendRequest(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _removeFriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text('Remove ${user?.title ?? 'this user'} from your friends?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.removeFriend(widget.userId);
      if (!mounted) return;
      await context.read<ChatController>().refreshInbox();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend removed')),
        );
        setState(() {});
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reportUser() async {
    final colors = context.read<ThemeController>().colors;
    const reasons = <(String, String)>[
      ('spam', 'Spam'),
      ('harassment', 'Harassment'),
      ('impersonation', 'Impersonation'),
      ('inappropriate_content', 'Inappropriate Content'),
      ('scam_or_fraud', 'Scam or Fraud'),
      ('other', 'Other'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('Report user', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800))),
            ...reasons.map(
              (r) => ListTile(
                title: Text(r.$2, style: TextStyle(color: colors.textPrimary)),
                onTap: () => Navigator.pop(ctx, r.$1),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<AuthController>().api.reportUser(userId: widget.userId, reason: picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleBlock() async {
    final api = context.read<AuthController>().api;
    final chat = context.read<ChatController>();
    final wasBlocked = _isBlocked;
    try {
      if (wasBlocked) {
        await api.unblockUser(widget.userId);
      } else {
        await api.blockUser(widget.userId);
      }
      await chat.refreshInbox();
      if (mounted) {
        _blockedOverride = !wasBlocked;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wasBlocked ? 'User unblocked' : 'User blocked')),
        );
        setState(() {});
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final online = _isOnline;
    final u = user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
              : u == null
                  ? const Center(child: Text('User not found'))
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(
                          child: UserAvatar(
                            name: u.title,
                            userId: u.id,
                            hasAvatar: u.hasAvatar,
                            size: 96,
                            online: online,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            u.title,
                            style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text('@${u.username}', style: TextStyle(color: colors.textMuted, fontSize: 14)),
                        ),
                        if (u.birthday != null && !u.birthdayLocked) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '🎂 ${u.birthday!.month.toString().padLeft(2, '0')}/${u.birthday!.day.toString().padLeft(2, '0')}',
                              style: TextStyle(color: colors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ],
                        if (u.bio.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              u.bio,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.textSecondary, fontSize: 14),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            formatLastSeen(u.lastLoginAt, online: online),
                            style: TextStyle(
                              color: online ? colors.success : colors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_isOwn || highlights.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 92,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                if (_isOwn)
                                  _HighlightRing(
                                    label: 'New',
                                    colors: colors,
                                    isAdd: true,
                                    onTap: () => _createHighlight(),
                                  ),
                                ...highlights.map(
                                  (h) => _HighlightRing(
                                    label: h.name,
                                    colors: colors,
                                    coverFuture: h.hasCover
                                        ? context.read<AuthController>().api.getHighlightCover(h.id)
                                        : null,
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('${h.name} · ${h.itemCount} items')),
                                      );
                                    },
                                    onLongPress: _isOwn
                                        ? () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (d) => AlertDialog(
                                                title: const Text('Delete highlight?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                                                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                                                ],
                                              ),
                                            );
                                            if (ok == true && mounted) {
                                              try {
                                                await context.read<AuthController>().api.deleteHighlight(h.id);
                                                await _load();
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                                }
                                              }
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!_isOwn) ...[
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ActionButton(
                                icon: Icons.message_outlined,
                                label: 'Message',
                                color: colors.accent,
                                onTap: _sendMessage,
                              ),
                              const SizedBox(width: 24),
                              if (_isFriend)
                                _ActionButton(
                                  icon: Icons.person_remove_outlined,
                                  label: 'Unfriend',
                                  color: colors.error,
                                  onTap: _removeFriend,
                                )
                              else
                                _ActionButton(
                                  icon: Icons.person_add_outlined,
                                  label: 'Add Friend',
                                  color: colors.accentCyan,
                                  onTap: _sendFriendRequest,
                                ),
                              const SizedBox(width: 24),
                              _ActionButton(
                                icon: _isBlocked ? Icons.lock_open : Icons.block,
                                label: _isBlocked ? 'Unblock' : 'Block',
                                color: colors.error,
                                onTap: _toggleBlock,
                              ),
                              const SizedBox(width: 24),
                              _ActionButton(
                                icon: Icons.flag_outlined,
                                label: 'Report',
                                color: colors.error,
                                onTap: _reportUser,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
    );
  }

  Future<void> _createHighlight() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New highlight'),
        content: TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<AuthController>().api.createHighlight(name: name);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _HighlightRing extends StatelessWidget {
  const _HighlightRing({
    required this.label,
    required this.colors,
    required this.onTap,
    this.onLongPress,
    this.coverFuture,
    this.isAdd = false,
  });

  final String label;
  final dynamic colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Future<Uint8List?>? coverFuture;
  final bool isAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(40),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.accent, width: 2),
                color: colors.elevated,
              ),
              clipBehavior: Clip.antiAlias,
              child: isAdd
                  ? Icon(Icons.add, color: colors.accent)
                  : coverFuture == null
                      ? Icon(Icons.bookmark_outline, color: colors.accentCyan)
                      : FutureBuilder<Uint8List?>(
                          future: coverFuture,
                          builder: (context, snap) {
                            if (snap.data == null) {
                              return Icon(Icons.bookmark_outline, color: colors.accentCyan);
                            }
                            return Image.memory(snap.data!, fit: BoxFit.cover);
                          },
                        ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.read<ThemeController>().colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
