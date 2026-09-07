import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../widgets/image_lightbox.dart';

/// Gallery of shared media in the open chat (photos / files).
class ChatMediaScreen extends StatefulWidget {
  const ChatMediaScreen({super.key});

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  final cache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  List<ChatMessage> _items(ChatController chat, String filter) {
    return chat.messages.where((m) {
      final att = m.attachment;
      if (att == null || m.viewOnce) return false;
      if (filter == 'image') return att.isImage;
      if (filter == 'file') return !att.isImage && !att.isAudio;
      return true; // all media attachments
    }).toList();
  }

  Future<void> _openImage(ChatMessage message, QcColors colors) async {
    final chat = context.read<ChatController>();
    final id = message.attachment?.id;
    if (id == null) return;
    var bytes = cache[id];
    bytes ??= await chat.decryptAttachment(message);
    if (bytes == null || !mounted) return;
    cache[id] = bytes;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageLightbox(
          bytes: bytes!,
          filename: message.attachment?.filename ?? 'image',
          timestamp: message.createdAt,
          colors: colors,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared media'),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Photos'),
            Tab(text: 'Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          _grid(_items(chat, 'all'), colors),
          _grid(_items(chat, 'image'), colors),
          _list(_items(chat, 'file'), colors),
        ],
      ),
    );
  }

  Widget _empty(QcColors colors) => Center(
        child: Text('No media yet', style: TextStyle(color: colors.textMuted)),
      );

  Widget _grid(List<ChatMessage> items, QcColors colors) {
    if (items.isEmpty) return _empty(colors);
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final m = items[i];
        final att = m.attachment!;
        if (att.isImage) {
          return _ImageThumb(
            message: m,
            colors: colors,
            cache: cache,
            onTap: () => _openImage(m, colors),
          );
        }
        return Material(
          color: colors.elevated,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {},
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  att.isAudio ? Icons.mic : Icons.insert_drive_file_outlined,
                  color: colors.accentCyan,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    att.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(List<ChatMessage> items, QcColors colors) {
    if (items.isEmpty) return _empty(colors);
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
      itemBuilder: (ctx, i) {
        final att = items[i].attachment!;
        return ListTile(
          leading: Icon(Icons.insert_drive_file_outlined, color: colors.accentCyan),
          title: Text(att.filename, style: TextStyle(color: colors.textPrimary)),
          subtitle: Text(
            '${(att.size / 1024).toStringAsFixed(0)} KB',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        );
      },
    );
  }
}

class _ImageThumb extends StatefulWidget {
  const _ImageThumb({
    required this.message,
    required this.colors,
    required this.cache,
    required this.onTap,
  });

  final ChatMessage message;
  final QcColors colors;
  final Map<String, Uint8List> cache;
  final VoidCallback onTap;

  @override
  State<_ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<_ImageThumb> {
  Uint8List? bytes;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.message.attachment?.id;
    if (id == null) return;
    final cached = widget.cache[id];
    if (cached != null) {
      setState(() => bytes = cached);
      return;
    }
    setState(() => loading = true);
    final data = await context.read<ChatController>().decryptAttachment(widget.message);
    if (!mounted) return;
    if (data != null) widget.cache[id] = data;
    setState(() {
      bytes = data;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.colors.elevated,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: bytes == null ? null : widget.onTap,
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
            : Center(
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.broken_image_outlined, color: widget.colors.textMuted),
              ),
      ),
    );
  }
}
