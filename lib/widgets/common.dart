import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../theme/qc_theme.dart';
import 'avatar_cache.dart';

const _avatarPalette = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF0D9488),
  Color(0xFFD97706),
  Color(0xFFDB2777),
  Color(0xFF059669),
  Color(0xFFDC2626),
  Color(0xFF0284C7),
  Color(0xFF4F46E5),
  Color(0xFFCA8A04),
];

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.userId,
    this.hasAvatar = false,
    this.isGroup = false,
    this.size = 44,
    this.online = false,
    this.imageBytes,
  });

  final String name;
  final String? userId;
  final bool hasAvatar;
  final bool isGroup;
  final double size;
  final bool online;
  final ImageProvider? imageBytes;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _loadedBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.hasAvatar != widget.hasAvatar ||
        oldWidget.isGroup != widget.isGroup ||
        oldWidget.imageBytes != widget.imageBytes) {
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    if (widget.imageBytes != null) {
      if (mounted) setState(() => _loadedBytes = null);
      return;
    }
    final id = widget.userId;
    if (id == null || id.isEmpty) {
      if (mounted) {
        setState(() {
          _loadedBytes = null;
          _loading = false;
        });
      }
      return;
    }

    // Group photos and user avatars: only fetch when the server says one exists.
    // Avoids N parallel 404s that freeze the home list on large directories.
    if (!widget.hasAvatar) {
      if (mounted) {
        setState(() {
          _loadedBytes = null;
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final api = context.read<AuthController>().api;
      final bytes = await AvatarCache.instance.load(api, id, isGroup: widget.isGroup);
      if (!mounted) return;
      setState(() {
        _loadedBytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadedBytes = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = QcColors.of(
      Theme.of(context).brightness == Brightness.light ? QcThemeId.light : QcThemeId.dark,
    );
    final idx = (widget.userId ?? widget.name).codeUnits.fold<int>(0, (a, b) => a + b) % _avatarPalette.length;
    final initials = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();

    Widget inner;
    if (widget.imageBytes != null) {
      inner = ClipOval(
        child: Image(image: widget.imageBytes!, width: widget.size, height: widget.size, fit: BoxFit.cover),
      );
    } else if (_loadedBytes != null) {
      inner = ClipOval(
        child: Image.memory(
          _loadedBytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else {
      inner = CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: _avatarPalette[idx],
        child: _loading
            ? SizedBox(
                width: widget.size * 0.35,
                height: widget.size * 0.35,
                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.size * 0.34,
                ),
              ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          inner,
          if (widget.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: widget.size * 0.28,
                height: widget.size * 0.28,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QcPrimaryButton extends StatelessWidget {
  const QcPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

int passwordScore(String password) {
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'\d').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  return score.clamp(0, 4);
}

class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password, required this.colors});
  final String password;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    final score = passwordScore(password);
    final labels = ['Too weak', 'Weak', 'Okay', 'Strong', 'Excellent'];
    final barColors = [
      colors.error,
      const Color(0xFFF59E0B),
      const Color(0xFFFBBF24),
      colors.success,
      colors.accentCyan,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                decoration: BoxDecoration(
                  color: i < score ? barColors[score] : colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          labels[score],
          style: TextStyle(color: barColors[score], fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

String formatLastSeen(DateTime? at, {bool online = false}) {
  if (online) return 'online';
  if (at == null) return 'never seen';
  final diff = DateTime.now().difference(at.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String formatMessageTime(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  final now = DateTime.now();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return '$hh:$mm';
  }
  return '${local.month}/${local.day} $hh:$mm';
}

QcUser? userFromConversation(Conversation c) => c.peer;
