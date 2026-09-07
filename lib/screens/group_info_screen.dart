import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../widgets/avatar_cache.dart';
import '../widgets/common.dart';
import 'user_profile_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  QcGroup? group;
  bool loading = true;
  String? error;
  List<GroupJoinRequest> joinRequests = [];
  bool loadingRequests = false;

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
      final g = await context.read<AuthController>().api.getGroup(widget.groupId);
      if (!mounted) return;
      setState(() => group = g);
      await context.read<ChatController>().refreshGroup(widget.groupId);
      await _loadJoinRequests();
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadJoinRequests() async {
    final g = group;
    final me = context.read<AuthController>().user;
    if (g == null || me == null) return;
    if (!g.isPublic || g.joinPolicy != 'request') return;
    if (!_isAdmin(me)) return;
    setState(() => loadingRequests = true);
    try {
      final list = await context.read<AuthController>().api.listJoinRequests(widget.groupId);
      if (!mounted) return;
      setState(() => joinRequests = list);
    } catch (_) {
      if (mounted) setState(() => joinRequests = []);
    } finally {
      if (mounted) setState(() => loadingRequests = false);
    }
  }

  bool _isAdmin(QcUser me) {
    final g = group;
    if (g == null) return false;
    return g.admins.map((e) => e.toString()).contains(me.id);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Edit name / description ──

  Future<void> _editGroupInfo() async {
    final g = group;
    if (g == null) return;
    final colors = context.read<ThemeController>().colors;
    final nameCtrl = TextEditingController(text: g.name);
    final descCtrl = TextEditingController(text: g.description);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Edit group', style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Group name')),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Description (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.updateGroup(widget.groupId, {
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  // ── Change group photo ──

  Future<void> _changeGroupPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    try {
      await context.read<AuthController>().api.uploadGroupPhoto(
            widget.groupId,
            bytes,
            filename: file.name,
            mime: file.mimeType ?? 'image/jpeg',
          );
      AvatarCache.instance.bust(widget.groupId);
      await _load();
      _snack('Group photo updated');
    } catch (e) {
      _snack('$e');
    }
  }

  // ── Invite link (admins) ──

  Future<void> _setInvite({required bool enabled, bool rotate = false}) async {
    try {
      final updated = await context.read<AuthController>().api.setGroupInvite(
            groupId: widget.groupId,
            enabled: enabled,
            rotate: rotate,
          );
      if (!mounted) return;
      setState(() => group = updated);
      await context.read<ChatController>().refreshGroup(widget.groupId);
      if (!enabled) {
        _snack('Invite link disabled');
      } else if (rotate) {
        _snack('Invite code rotated');
      } else {
        _snack('Invite link enabled');
      }
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _copyInviteCode() async {
    final code = group?.inviteCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    _snack('Invite code copied');
  }

  Future<void> _shareInvite() async {
    final g = group;
    final code = g?.inviteCode;
    if (g == null || code == null || code.isEmpty) return;
    await Share.share(
      'Join "${g.name}" on QuantumChat with invite code: $code',
      subject: 'QuantumChat group invite',
    );
  }

  // ── Promote / Demote admin ──

  Future<void> _toggleAdmin(QcUser member, bool isCurrentlyAdmin) async {
    try {
      if (isCurrentlyAdmin) {
        await context.read<AuthController>().api.demoteAdmin(widget.groupId, member.id);
      } else {
        await context.read<AuthController>().api.promoteAdmin(widget.groupId, member.id);
      }
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  // ── Delete group ──

  Future<void> _deleteGroup() async {
    final colors = context.read<ThemeController>().colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Delete group?', style: TextStyle(color: colors.textPrimary)),
        content: Text('This will permanently delete the group and all messages.', style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.deleteGroup(widget.groupId);
      if (!mounted) return;
      context.read<ChatController>().closeThread();
      Navigator.of(context).popUntil((r) => r.isFirst);
      await context.read<ChatController>().refreshInbox();
    } catch (e) {
      _snack('$e');
    }
  }

  // ── Add / Remove members ──

  Future<void> _addMember() async {
    final chat = context.read<ChatController>();
    final colors = context.read<ThemeController>().colors;
    final candidates = chat.users.where((u) => !(group?.members.any((m) => m.id == u.id) ?? false)).toList();
    final picked = await showModalBottomSheet<QcUser>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Add member')),
            ...candidates.map(
              (u) => ListTile(
                leading: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar),
                title: Text(u.title),
                subtitle: Text('@${u.username}'),
                onTap: () => Navigator.pop(ctx, u),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<AuthController>().api.addGroupMembers(widget.groupId, [picked.id]);
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _removeMember(QcUser member) async {
    final me = context.read<AuthController>().user!;
    final colors = context.read<ThemeController>().colors;
    final leaving = member.id == me.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          leaving ? 'Leave group?' : 'Remove member?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          leaving
              ? 'You will leave this group and stop receiving its messages.'
              : 'Remove ${member.title} from this group?',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              leaving ? 'Leave group' : 'Remove',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final api = context.read<AuthController>().api;
      if (leaving) {
        await api.leaveGroup(widget.groupId, me.id);
        if (!mounted) return;
        context.read<ChatController>().closeThread();
        Navigator.of(context).popUntil((r) => r.isFirst);
        await context.read<ChatController>().refreshInbox();
        return;
      }
      await api.removeGroupMember(widget.groupId, member.id);
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _leaveGroup() async {
    final me = context.read<AuthController>().user!;
    await _removeMember(me);
  }

  Future<void> _acceptJoinRequest(GroupJoinRequest req) async {
    try {
      await context.read<AuthController>().api.acceptJoinRequest(widget.groupId, req.user.id);
      await _load();
      _snack('Accepted @${req.user.username}');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _rejectJoinRequest(GroupJoinRequest req) async {
    try {
      await context.read<AuthController>().api.rejectJoinRequest(widget.groupId, req.user.id);
      if (!mounted) return;
      setState(() => joinRequests = joinRequests.where((r) => r.id != req.id).toList());
      _snack('Rejected @${req.user.username}');
    } catch (e) {
      _snack('$e');
    }
  }

  Widget _joinRequestsSection(QcColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Join requests', style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (loadingRequests)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (joinRequests.isEmpty)
          Text('No pending requests', style: TextStyle(color: colors.textMuted, fontSize: 13))
        else
          ...joinRequests.map((req) {
            final u = req.user;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar),
              title: Text(u.title, style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('@${u.username}', style: TextStyle(color: colors.textMuted)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Accept',
                    onPressed: () => _acceptJoinRequest(req),
                    icon: Icon(Icons.check_circle_outline, color: colors.accentCyan),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    onPressed: () => _rejectJoinRequest(req),
                    icon: Icon(Icons.cancel_outlined, color: colors.error),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _inviteLinkSection(QcColors colors) {
    final g = group!;
    final enabled = g.inviteEnabled && g.inviteCode != null && g.inviteCode!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invite link', style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          enabled
              ? 'Anyone with this code can join the group.'
              : 'Invite link is off. Enable it to let people join with a code.',
          style: TextStyle(color: colors.textMuted, fontSize: 13),
        ),
        if (enabled) ...[
          const SizedBox(height: 10),
          SelectableText(
            g.inviteCode!,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _copyInviteCode,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy code'),
              ),
              OutlinedButton.icon(
                onPressed: _shareInvite,
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Share'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!enabled)
              QcPrimaryButton(label: 'Enable', onPressed: () => _setInvite(enabled: true))
            else ...[
              OutlinedButton(
                onPressed: () => _setInvite(enabled: false),
                child: const Text('Disable'),
              ),
              OutlinedButton(
                onPressed: () => _setInvite(enabled: true, rotate: true),
                child: const Text('Rotate'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final me = context.watch<AuthController>().user!;
    final g = group;
    final admin = _isAdmin(me);

    return Scaffold(
      appBar: AppBar(title: Text(g?.name ?? 'Group')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
              : g == null
                  ? const Center(child: Text('Group not found'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: admin ? _changeGroupPhoto : null,
                            child: Stack(
                              children: [
                                UserAvatar(
                                  name: g.name,
                                  userId: g.id,
                                  hasAvatar: g.hasPhoto,
                                  isGroup: true,
                                  size: 72,
                                ),
                                if (admin)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(g.name, style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                            ),
                            if (admin) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Edit group',
                                onPressed: _editGroupInfo,
                                icon: Icon(Icons.edit, size: 18, color: colors.accentCyan),
                              ),
                            ],
                          ],
                        ),
                        if (g.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Center(child: Text(g.description, style: TextStyle(color: colors.textMuted))),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '${g.members.length} members',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (admin && g.isPublic && g.joinPolicy == 'request') _joinRequestsSection(colors),
                        if (admin) _inviteLinkSection(colors),
                        if (admin)
                          QcPrimaryButton(label: 'Add member', onPressed: _addMember),
                        const SizedBox(height: 16),
                        Text('Members', style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        ...g.members.map((m) {
                          final memberIsAdmin = g.admins.contains(m.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: GestureDetector(
                              onTap: m.id == me.id ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: m.id))),
                              child: UserAvatar(name: m.title, userId: m.id, hasAvatar: m.hasAvatar),
                            ),
                            title: Text(m.title, style: TextStyle(color: colors.textPrimary)),
                            subtitle: Text(
                              memberIsAdmin ? '@${m.username} · admin' : '@${m.username}',
                              style: TextStyle(color: colors.textMuted),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (admin && m.id != me.id)
                                  IconButton(
                                    tooltip: memberIsAdmin ? 'Remove admin' : 'Make admin',
                                    onPressed: () => _toggleAdmin(m, memberIsAdmin),
                                    icon: Icon(
                                      memberIsAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                                      color: memberIsAdmin ? colors.accentCyan : colors.textMuted,
                                    ),
                                  ),
                                if (m.id == me.id || admin)
                                  IconButton(
                                    tooltip: m.id == me.id ? 'Leave group' : 'Remove member',
                                    onPressed: () => _removeMember(m),
                                    icon: Icon(
                                      m.id == me.id ? Icons.logout : Icons.person_remove_outlined,
                                      color: colors.error,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: colors.error, side: BorderSide(color: colors.error)),
                          onPressed: _leaveGroup,
                          child: const Text('Leave group'),
                        ),
                        if (admin) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: colors.error, side: BorderSide(color: colors.error)),
                            onPressed: _deleteGroup,
                            child: const Text('Delete group'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}
