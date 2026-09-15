import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme/qc_theme.dart';
import '../utils/message_preview.dart';

/// WhatsApp-style message actions: quick reactions + reply / edit / delete / copy / forward / pin / star.
Future<String?> showMessageActionsSheet({
  required BuildContext context,
  required ChatMessage message,
  required QcColors colors,
  required bool mine,
  bool isGroup = false,
}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.surface,
    showDragHandle: true,
    builder: (ctx) {
      final preview = getMessagePreviewText(message.text, isMine: mine);
      final previewLine = preview.isNotEmpty
          ? preview
          : (message.attachment != null ? '📎 Attachment' : 'Message');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                previewLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text('React', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🔥']
                    .map(
                      (e) => Material(
                        color: colors.elevated,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(ctx, 'react:$e'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text(e, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.reply,
                label: 'Reply',
                colors: colors,
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              _ActionTile(
                icon: Icons.forward,
                label: 'Forward',
                colors: colors,
                onTap: () => Navigator.pop(ctx, 'forward'),
              ),
              _ActionTile(
                icon: message.isStarred ? Icons.star : Icons.star_border,
                label: message.isStarred ? 'Unstar' : 'Star',
                colors: colors,
                onTap: () => Navigator.pop(ctx, 'star'),
              ),
              if (isGroup)
                _ActionTile(
                  icon: Icons.push_pin,
                  label: message.isPinned ? 'Unpin' : 'Pin',
                  colors: colors,
                  onTap: () => Navigator.pop(ctx, 'pin'),
                ),
              if (message.text != null && message.text!.isNotEmpty)
                _ActionTile(
                  icon: Icons.copy,
                  label: 'Copy text',
                  colors: colors,
                  onTap: () => Navigator.pop(ctx, 'copy'),
                ),
              if (mine && message.attachment == null && message.text != null && message.text!.isNotEmpty)
                _ActionTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  colors: colors,
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              _ActionTile(
                icon: Icons.info_outline,
                label: 'Message info',
                colors: colors,
                onTap: () => Navigator.pop(ctx, 'info'),
              ),
              if (message.editedAt != null)
                _ActionTile(
                  icon: Icons.history,
                  label: 'Edit history',
                  colors: colors,
                  onTap: () => Navigator.pop(ctx, 'edit_history'),
                ),
              if (mine)
                _ActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete for everyone',
                  colors: colors,
                  danger: true,
                  onTap: () => Navigator.pop(ctx, 'delete_everyone'),
                ),
              _ActionTile(
                icon: Icons.delete_forever_outlined,
                label: 'Delete for me',
                colors: colors,
                onTap: () => Navigator.pop(ctx, 'delete_me'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final QcColors colors;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? colors.error : colors.textPrimary;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: fg, size: 22),
      title: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
