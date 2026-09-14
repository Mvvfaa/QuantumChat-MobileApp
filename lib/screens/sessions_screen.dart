import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../crypto/key_storage.dart';
import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import 'device_link_sheet.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> sessions = [];

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
      final data = await context.read<AuthController>().api.listSessions();
      if (mounted) setState(() => sessions = data);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _revoke(String sessionId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = context.read<ThemeController>().colors;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text('Revoke session?', style: TextStyle(color: colors.textPrimary)),
          content: Text('This will log out that device.', style: TextStyle(color: colors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke')),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AuthController>().api.revokeSession(sessionId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session revoked')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final currentSessionId = KeyStorage.instance.getSessionId();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Sessions'),
        actions: [
          TextButton.icon(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: colors.surface,
                isScrollControlled: true,
                builder: (_) => const DeviceLinkSheet(),
              );
            },
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: const Text('Link a device'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
              : sessions.isEmpty
                  ? Center(child: Text('No sessions found', style: TextStyle(color: colors.textMuted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => Divider(color: colors.border.withValues(alpha: 0.5)),
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        final id = '${s['_id'] ?? s['id'] ?? ''}';
                        final isCurrent = s['isCurrent'] == true || id == currentSessionId;
                        final label = s['deviceLabel'] as String? ?? 'Unknown device';
                        final lastActive = s['lastActiveAt'] as String? ?? s['updatedAt'] as String? ?? '';

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _deviceIcon(label),
                            color: isCurrent ? colors.accent : colors.textMuted,
                            size: 28,
                          ),
                          title: Row(
                            children: [
                              Flexible(child: Text(label, style: TextStyle(color: colors.textPrimary))),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colors.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('This device', style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: lastActive.isNotEmpty
                              ? Text(_formatTime(lastActive), style: TextStyle(color: colors.textMuted, fontSize: 12))
                              : null,
                          trailing: isCurrent
                              ? null
                              : IconButton(
                                  tooltip: 'Revoke',
                                  onPressed: () => _revoke(id),
                                  icon: Icon(Icons.logout, color: colors.error),
                                ),
                        );
                      },
                    ),
    );
  }

  IconData _deviceIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('mobile') || l.contains('android') || l.contains('ios') || l.contains('phone')) return Icons.phone_android;
    if (l.contains('tablet') || l.contains('ipad')) return Icons.tablet;
    return Icons.devices;
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 2) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
