import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/chat_controller.dart';
import '../theme/qc_theme.dart';
import 'image_lightbox.dart';

class AttachmentBubble extends StatefulWidget {
  const AttachmentBubble({
    super.key,
    required this.message,
    required this.colors,
  });

  final ChatMessage message;
  final QcColors colors;

  @override
  State<AttachmentBubble> createState() => _AttachmentBubbleState();
}

class _AttachmentBubbleState extends State<AttachmentBubble> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.message.attachment == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await context.read<ChatController>().decryptAttachment(widget.message);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        if (bytes == null) _error = 'Could not decrypt';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.message.attachment;
    if (att == null) return const SizedBox.shrink();

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: widget.colors.error, fontSize: 12));
    }
    if (_bytes != null && att.isImage) {
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageLightbox(
                bytes: _bytes!,
                filename: att.filename,
                timestamp: widget.message.createdAt,
                colors: widget.colors,
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            _bytes!,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _FileChip(att: att, colors: widget.colors),
          ),
        ),
      );
    }
    if (_bytes != null && att.isAudio) {
      return _VoicePlayer(
        bytes: _bytes!,
        filename: att.filename,
        colors: widget.colors,
      );
    }
    return _FileChip(att: att, colors: widget.colors);
  }
}

class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({
    required this.bytes,
    required this.filename,
    required this.colors,
  });

  final Uint8List bytes;
  final String filename;
  final QcColors colors;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _ready = false;
  bool _playing = false;
  String? _tempPath;
  double _speed = 1.0;
  static const _speeds = [1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = _extFor(widget.filename);
      final file = File('${dir.path}/qc-voice-${DateTime.now().microsecondsSinceEpoch}.$ext');
      await file.writeAsBytes(widget.bytes, flush: true);
      _tempPath = file.path;
      final dur = await _player.setFilePath(file.path);
      if (!mounted) return;
      setState(() {
        _duration = dur ?? Duration.zero;
        _ready = true;
      });
      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  String _extFor(String filename) {
    final lower = filename.toLowerCase();
    for (final e in ['m4a', 'aac', 'mp3', 'wav', 'ogg', 'webm']) {
      if (lower.endsWith('.$e')) return e;
    }
    return 'm4a';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _cycleSpeed() async {
    if (!_ready) return;
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    await _player.setSpeed(next);
    if (mounted) setState(() => _speed = next);
  }

  String get _speedLabel {
    if (_speed == 1.0) return '1x';
    if (_speed == 1.5) return '1.5x';
    return '2x';
  }

  @override
  void dispose() {
    _player.dispose();
    final path = _tempPath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final display = _playing || _position > Duration.zero
        ? _position
        : (_duration > Duration.zero ? _duration : Duration.zero);
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: _ready ? _toggle : null,
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: colors.accentCyan,
              size: 36,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _ready ? progress : null,
                    minHeight: 4,
                    backgroundColor: colors.border.withValues(alpha: 0.5),
                    color: colors.accentCyan,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmt(display),
                  style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _ready ? _cycleSpeed : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: colors.accentCyan,
            ),
            child: Text(
              _speedLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.att, required this.colors});
  final AttachmentMeta att;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: colors.accentCyan, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            att.filename,
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
