import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../screens/story_archive_screen.dart';
import '../screens/story_drafts_screen.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import 'common.dart';

class StoriesRail extends StatelessWidget {
  const StoriesRail({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;
    final me = context.watch<AuthController>().user;
    if (me == null) return const SizedBox.shrink();

    final byUser = <String, StoryItem>{};
    for (final s in chat.stories) {
      final prev = byUser[s.userId];
      if (prev == null || (s.createdAt != null && (prev.createdAt == null || s.createdAt!.isAfter(prev.createdAt!)))) {
        byUser[s.userId] = s;
      }
    }
    final items = byUser.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          _AddStoryChip(
            colors: colors,
            onTap: () => _showCreateMenu(context),
            onLongPress: () => _showCreateMenu(context),
          ),
          ...items.map(
            (s) => _StoryChip(
              story: s,
              colors: colors,
              onTap: () => _openStory(context, s),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    final colors = context.read<ThemeController>().colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo story'),
              onTap: () {
                Navigator.pop(ctx);
                _createPhotoStory(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text story'),
              onTap: () {
                Navigator.pop(ctx);
                _createTextStory(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drafts_outlined),
              title: const Text('Drafts'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryDraftsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Archive'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryArchiveScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPhotoStory(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    try {
      await context.read<ChatController>().postStory(
            bytes,
            filename: file.name,
            mimetype: file.mimeType ?? 'image/jpeg',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story posted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _createTextStory(BuildContext context) async {
    final colors = context.read<ThemeController>().colors;
    final textCtrl = TextEditingController();
    var bg = const Color(0xFF1F2937);
    const palette = <Color>[
      Color(0xFF1F2937),
      Color(0xFF7C3AED),
      Color(0xFF0D9488),
      Color(0xFFDB2777),
      Color(0xFFD97706),
      Color(0xFF2563EB),
    ];
    String status = 'published';
    DateTime? publishAt;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Text story', style: TextStyle(color: colors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textCtrl,
                      maxLines: 4,
                      maxLength: 200,
                      decoration: const InputDecoration(hintText: 'Write something…'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: palette.map((c) {
                        return GestureDetector(
                          onTap: () => setLocal(() => bg = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: bg == c ? colors.accentCyan : Colors.white24, width: 2),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 120,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        textCtrl.text.isEmpty ? 'Preview' : textCtrl.text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    status = 'draft';
                    Navigator.pop(ctx, 'ok');
                  },
                  child: const Text('Save draft'),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 30)),
                      initialDate: now.add(const Duration(hours: 1)),
                    );
                    if (picked == null || !ctx.mounted) return;
                    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
                    if (time == null || !ctx.mounted) return;
                    publishAt = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                    status = 'scheduled';
                    Navigator.pop(ctx, 'ok');
                  },
                  child: const Text('Schedule'),
                ),
                FilledButton(
                  onPressed: () {
                    status = 'published';
                    Navigator.pop(ctx, 'ok');
                  },
                  child: const Text('Post'),
                ),
              ],
            );
          },
        );
      },
    );

    final text = textCtrl.text.trim();
    textCtrl.dispose();
    if (result != 'ok' || text.isEmpty || !context.mounted) return;

    try {
      final png = await renderTextStoryPng(text: text, background: bg);
      await context.read<ChatController>().postStory(
            png,
            filename: 'text-story.png',
            mimetype: 'image/png',
            mediaType: 'image',
            status: status,
            publishAt: publishAt?.toUtc().toIso8601String(),
            caption: text,
          );
      if (context.mounted) {
        final msg = status == 'draft'
            ? 'Draft saved'
            : status == 'scheduled'
                ? 'Story scheduled'
                : 'Story posted';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openStory(BuildContext context, StoryItem story) async {
    final colors = context.read<ThemeController>().colors;
    final api = context.read<AuthController>().api;
    final me = context.read<AuthController>().user;
    final chat = context.read<ChatController>();
    final isOwn = me != null && story.userId == me.id;
    Uint8List? mediaBytes;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return FutureBuilder<Uint8List?>(
          future: () async {
            await api.markStoryViewed(story.id);
            mediaBytes = await api.getStoryMedia(story.id);
            return mediaBytes;
          }(),
          builder: (context, snap) {
            Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = const CircularProgressIndicator();
            } else if (snap.data == null) {
              body = Text('Could not load story', style: TextStyle(color: colors.textPrimary));
            } else {
              body = InteractiveViewer(child: Image.memory(snap.data!, fit: BoxFit.contain));
            }
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: UserAvatar(name: story.username, userId: story.userId, hasAvatar: story.hasAvatar, size: 36),
                    title: Text(story.username, style: const TextStyle(color: Colors.white)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isOwn)
                          IconButton(
                            tooltip: 'Viewers',
                            onPressed: () => _showViewers(ctx, story.id),
                            icon: const Icon(Icons.visibility_outlined, color: Colors.white),
                          ),
                        if (isOwn)
                          IconButton(
                            tooltip: 'Save to highlight',
                            onPressed: () async {
                              final bytes = snap.data;
                              if (bytes == null) return;
                              await _saveToHighlight(ctx, story, bytes);
                            },
                            icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                          ),
                        if (isOwn)
                          IconButton(
                            tooltip: 'Delete story',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('Delete this story?'),
                                  content: const Text('This story will be removed for everyone.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (confirm == true && ctx.mounted) {
                                try {
                                  await api.deleteStory(story.id);
                                  await chat.refreshStories();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                      maxWidth: MediaQuery.of(context).size.width,
                    ),
                    child: Center(child: body),
                  ),
                  if (!isOwn)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((emoji) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              try {
                                await api.reactToStory(story.id, emoji);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Reaction sent')),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(emoji, style: const TextStyle(fontSize: 28)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (isOwn) const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showViewers(BuildContext context, String storyId) async {
    final api = context.read<AuthController>().api;
    final colors = context.read<ThemeController>().colors;
    List<Map<String, dynamic>> viewers = [];
    try {
      viewers = await api.getStoryViewers(storyId);
    } catch (_) {}
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Viewers (${viewers.length})', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            ),
            if (viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No viewers yet', style: TextStyle(color: colors.textMuted)),
              )
            else
              ...viewers.take(30).map((v) {
                final user = v['user'] is Map ? Map<String, dynamic>.from(v['user'] as Map) : null;
                final name = user?['username']?.toString() ?? v['username']?.toString() ?? 'User';
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(name, style: TextStyle(color: colors.textPrimary)),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToHighlight(BuildContext context, StoryItem story, Uint8List bytes) async {
    final api = context.read<AuthController>().api;
    final colors = context.read<ThemeController>().colors;
    List<HighlightItem> highlights = [];
    try {
      highlights = await api.listHighlights();
    } catch (_) {}
    if (!context.mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Save to highlight', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New highlight'),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
            ...highlights.map(
              (h) => ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(h.name),
                subtitle: Text('${h.itemCount} items'),
                onTap: () => Navigator.pop(ctx, h.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    try {
      var highlightId = picked;
      if (picked == '__new__') {
        final nameCtrl = TextEditingController();
        final name = await showDialog<String>(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Highlight name'),
            content: TextField(controller: nameCtrl, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, nameCtrl.text.trim()),
                child: const Text('Create'),
              ),
            ],
          ),
        );
        nameCtrl.dispose();
        if (name == null || name.isEmpty || !context.mounted) return;
        final created = await api.createHighlight(name: name);
        highlightId = created.id;
      }
      await api.addHighlightItem(
        highlightId: highlightId,
        bytes: bytes,
        filename: 'highlight.jpg',
        mimetype: story.mimetype,
        sourceStoryId: story.id,
        caption: story.caption,
        mediaType: story.mediaType == 'text' ? 'image' : story.mediaType,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to highlight')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

Future<Uint8List> renderTextStoryPng({
  required String text,
  required Color background,
  int width = 720,
  int height = 1280,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  final paint = Paint()..color = background;
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);

  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 12),
  )
    ..pushStyle(ui.TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700))
    ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: width - 80.0));
  final dy = (height - paragraph.height) / 2;
  canvas.drawParagraph(paragraph, Offset(40, dy.clamp(40, height - 40.0)));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) throw Exception('Failed to render text story');
  return byteData.buffer.asUint8List();
}

class _AddStoryChip extends StatelessWidget {
  const _AddStoryChip({required this.colors, required this.onTap, this.onLongPress});
  final dynamic colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
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
              child: Icon(Icons.add, color: colors.accent),
            ),
            const SizedBox(height: 6),
            Text('Your story', style: TextStyle(color: colors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _StoryChip extends StatelessWidget {
  const _StoryChip({required this.story, required this.colors, required this.onTap});
  final StoryItem story;
  final dynamic colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [colors.accent, colors.accentCyan]),
              ),
              child: UserAvatar(name: story.username, userId: story.userId, hasAvatar: story.hasAvatar, size: 54),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                story.username,
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
