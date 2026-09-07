import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../utils/screenshot_protection.dart';
import '../widgets/attachment_bubble.dart';
import '../widgets/clear_chat_sheet.dart';
import '../widgets/common.dart';
import '../widgets/edit_history_sheet.dart';
import '../widgets/forward_sheet.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/gif_picker_sheet.dart';
import '../widgets/group_message_content.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/linkified_text.dart';
import '../widgets/mention_overlay.dart';
import '../widgets/message_actions_sheet.dart';
import '../widgets/message_info_sheet.dart';
import '../widgets/theme_scene.dart';
import '../crypto/key_storage.dart';
import 'chat_media_screen.dart';
import 'group_info_screen.dart';
import 'user_profile_screen.dart';
import 'wallpaper_screen.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final composer = TextEditingController();
  final scroll = ScrollController();
  final searchCtrl = TextEditingController();
  bool searching = false;
  String searchQuery = '';
  bool _showEmojiPicker = false;
  final _composerFocus = FocusNode();
  final _composerLayerLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  Timer? _liveRefresh;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordPath;
  static const int _maxRecordSeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<ChatController>().refreshOpenThread());
      _syncScreenshotProtection();
    });
    _liveRefresh = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      unawaited(context.read<ChatController>().refreshOpenThread());
    });
  }

  void _syncScreenshotProtection() {
    final chat = context.read<ChatController>();
    final me = context.read<AuthController>().user;
    final conv = chat.selected;
    var enforce = false;
    if (conv != null && me != null) {
      if (conv.type == ConversationType.dm && !conv.isSelfChat) {
        enforce = userRequiresScreenshotProtection(conv.peer);
      } else if (conv.type == ConversationType.group) {
        enforce = groupHasProtectedMember(conv.group, me.id);
      }
    }
    unawaited(setSecureFlag(enforce));
  }

  @override
  void dispose() {
    unawaited(setSecureFlag(false));
    _liveRefresh?.cancel();
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    _removeMentionOverlay();
    composer.dispose();
    scroll.dispose();
    searchCtrl.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
  }

  void _onComposerChangedWithMentions(String value, ChatController chat) {
    chat.onComposerChanged(value);
    final conv = chat.selected;
    if (conv == null || conv.type != ConversationType.group) {
      _removeMentionOverlay();
      return;
    }
    final cursor = composer.selection.baseOffset;
    if (cursor <= 0) {
      _removeMentionOverlay();
      return;
    }
    final textBefore = value.substring(0, cursor);
    final atMatch = RegExp(r'@(\w*)$').firstMatch(textBefore);
    if (atMatch == null) {
      _removeMentionOverlay();
      return;
    }
    final query = atMatch.group(1)?.toLowerCase() ?? '';
    final group = conv.group;
    if (group == null) {
      _removeMentionOverlay();
      return;
    }
    final members = group.members
        .where((m) => m.id != chat.me.id)
        .where((m) =>
            query.isEmpty ||
            m.username.toLowerCase().contains(query) ||
            m.displayName.toLowerCase().contains(query))
        .toList();
    if (members.isEmpty) {
      _removeMentionOverlay();
      return;
    }
    _removeMentionOverlay();
    final colors = context.read<ThemeController>().colors;
    _mentionOverlay = OverlayEntry(
      builder: (ctx) => MentionOverlay(
        link: _composerLayerLink,
        members: members,
        colors: colors,
        onSelect: (user) {
          _removeMentionOverlay();
          final start = atMatch.start;
          final end = cursor;
          final replacement = '@${user.username} ';
          composer.text = value.substring(0, start) + replacement + value.substring(end);
          composer.selection = TextSelection.collapsed(offset: start + replacement.length);
        },
      ),
    );
    Overlay.of(context).insert(_mentionOverlay!);
  }

  Future<void> _send() async {
    final chat = context.read<ChatController>();
    if (chat.sending) return;
    final text = composer.text.trim();
    if (text.isEmpty) return;
    composer.clear();
    await chat.sendText(text);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  List<ChatMessage> _visible(ChatController chat) {
    if (searchQuery.trim().isEmpty) return chat.messages;
    final q = searchQuery.trim().toLowerCase();
    return chat.messages.where((m) => (m.text ?? '').toLowerCase().contains(q)).toList();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _confirmAndSendMedia(
      bytes: bytes,
      filename: file.name,
      mimetype: file.mimeType ?? 'image/jpeg',
      isVideo: false,
    );
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _confirmAndSendMedia(
      bytes: bytes,
      filename: file.name,
      mimetype: file.mimeType ?? 'video/mp4',
      isVideo: true,
    );
  }

  Future<void> _confirmAndSendMedia({
    required Uint8List bytes,
    required String filename,
    required String mimetype,
    required bool isVideo,
  }) async {
    final colors = context.read<ThemeController>().colors;
    var viewOnce = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: colors.surface,
            title: Text(
              isVideo ? 'Send video' : 'Send photo',
              style: TextStyle(color: colors.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isVideo
                      ? Container(
                          height: 160,
                          width: double.infinity,
                          color: colors.elevated,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam, size: 40, color: colors.accentCyan),
                              const SizedBox(height: 8),
                              Text(filename, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                            ],
                          ),
                        )
                      : Image.memory(
                          bytes,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: viewOnce,
                      onChanged: (v) => setLocal(() => viewOnce = v ?? false),
                      activeColor: colors.accent,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocal(() => viewOnce = !viewOnce),
                        child: Text('View once', style: TextStyle(color: colors.textPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await context.read<ChatController>().sendAttachmentBytes(
          bytes: bytes,
          filename: filename,
          mimetype: mimetype,
          viewOnce: viewOnce,
        );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    await context.read<ChatController>().sendAttachmentBytes(
          bytes: bytes,
          filename: f.name,
          mimetype: f.extension != null ? 'application/${f.extension}' : 'application/octet-stream',
        );
  }

  String _fmtRecordTime(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startVoiceRecording() async {
    if (_recording || context.read<ChatController>().sending) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for voice notes')),
        );
      }
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-note-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordSeconds = 0;
        _recordPath = path;
        _showEmojiPicker = false;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_recording) {
          t.cancel();
          return;
        }
        setState(() => _recordSeconds++);
        if (_recordSeconds >= _maxRecordSeconds) {
          unawaited(_stopAndSendVoice());
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    final path = _recordPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _recordSeconds = 0;
        _recordPath = null;
      });
    }
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _recordPath;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
      _recordPath = null;
    });
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.isEmpty || !mounted) return;
    await context.read<ChatController>().sendAttachmentBytes(
          bytes: bytes,
          filename: 'voice-note-${DateTime.now().millisecondsSinceEpoch}.m4a',
          mimetype: 'audio/m4a',
        );
  }

  Future<void> _attachSheet() async {
    final colors = context.read<ThemeController>().colors;
    final chat = context.read<ChatController>();
    final isGroup = chat.selected?.type == ConversationType.group;
    QcGroup? group = chat.selected?.group;
    if (group == null && isGroup) {
      final id = chat.selected!.id;
      for (final g in chat.groups) {
        if (g.id == id) {
          group = g;
          break;
        }
      }
    }
    final isAdmin = group != null && group.isAdmin(chat.me.id);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: const Text('GIF'),
              onTap: () {
                Navigator.pop(ctx);
                showGifPickerSheet(context);
              },
            ),
            if (isGroup) ...[
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: const Text('Poll'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createPollDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Event'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createEventDialog();
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Announce'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _createAnnouncementDialog();
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createPollDialog() async {
    final colors = context.read<ThemeController>().colors;
    final questionCtrl = TextEditingController();
    final optionCtrls = List.generate(2, (_) => TextEditingController());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Create poll', style: TextStyle(color: colors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: questionCtrl,
                      decoration: const InputDecoration(labelText: 'Question'),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(optionCtrls.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextField(
                          controller: optionCtrls[i],
                          decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                        ),
                      );
                    }),
                    if (optionCtrls.length < 6)
                      TextButton.icon(
                        onPressed: () {
                          setLocal(() => optionCtrls.add(TextEditingController()));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add option'),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
              ],
            );
          },
        );
      },
    );

    final question = questionCtrl.text;
    final options = optionCtrls.map((c) => c.text).toList();
    for (final c in [...optionCtrls, questionCtrl]) {
      c.dispose();
    }
    if (ok != true || !mounted) return;
    await context.read<ChatController>().sendPoll(question, options);
  }

  Future<void> _createEventDialog() async {
    final colors = context.read<ThemeController>().colors;
    final titleCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? when = DateTime.now().add(const Duration(days: 1));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final whenLabel = when == null
                ? 'Pick date & time'
                : '${when!.year.toString().padLeft(4, '0')}-'
                    '${when!.month.toString().padLeft(2, '0')}-'
                    '${when!.day.toString().padLeft(2, '0')} '
                    '${when!.hour.toString().padLeft(2, '0')}:'
                    '${when!.minute.toString().padLeft(2, '0')}';
            return AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Create event', style: TextStyle(color: colors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title'),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.schedule, color: colors.accentCyan),
                      title: Text(whenLabel, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: when ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                        );
                        if (date == null || !ctx.mounted) return;
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(when ?? DateTime.now()),
                        );
                        if (time == null) return;
                        setLocal(() {
                          when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                        });
                      },
                    ),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(labelText: 'Location'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
              ],
            );
          },
        );
      },
    );

    final title = titleCtrl.text;
    final location = locationCtrl.text;
    final notes = notesCtrl.text;
    final whenIso = when?.toUtc().toIso8601String();
    titleCtrl.dispose();
    locationCtrl.dispose();
    notesCtrl.dispose();
    if (ok != true || !mounted) return;
    await context.read<ChatController>().sendEvent(
          title: title,
          when: whenIso,
          location: location,
          notes: notes,
        );
  }

  Future<void> _createAnnouncementDialog() async {
    final colors = context.read<ThemeController>().colors;
    final bodyCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Announcement', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: bodyCtrl,
          decoration: const InputDecoration(labelText: 'Message'),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );

    final body = bodyCtrl.text;
    bodyCtrl.dispose();
    if (ok != true || !mounted) return;
    await context.read<ChatController>().sendAnnouncement(body);
  }

  Future<void> _chatOptions() async {
    final chat = context.read<ChatController>();
    final colors = context.read<ThemeController>().colors;
    final conv = chat.selected;
    if (conv == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conv.type == ConversationType.group)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Group info'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GroupInfoScreen(groupId: conv.id)),
                  );
                },
              ),
            ListTile(
              leading: Icon(conv.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
              title: Text(conv.muted ? 'Unmute' : 'Mute'),
              onTap: () async {
                Navigator.pop(ctx);
                if (conv.muted) {
                  await chat.unmuteSelected();
                } else {
                  await chat.muteSelected();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Disappearing messages'),
              subtitle: Text(
                chat.disappearSeconds > 0
                    ? _disappearLabel(chat.disappearSeconds)
                    : 'Off',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDisappearSheet();
              },
            ),
            ListTile(
              leading: Icon(conv.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(conv.archived ? 'Unarchive' : 'Archive'),
              onTap: () async {
                Navigator.pop(ctx);
                await chat.toggleArchiveSelected();
              },
            ),
            if (conv.type == ConversationType.dm && !conv.isSelfChat)
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide chat'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await chat.hideSelectedChat();
                  if (mounted) Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Shared media'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatMediaScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear chat'),
              onTap: () async {
                Navigator.pop(ctx);
                final scopes = await showClearChatSheet(context, colors: colors);
                if (scopes == null || scopes.isEmpty || !mounted) return;
                await chat.clearSelectedChat(scopes: scopes);
              },
            ),
            if (conv.type == ConversationType.dm && !conv.isSelfChat)
              ListTile(
                leading: Icon(Icons.block, color: colors.error),
                title: Text('Block', style: TextStyle(color: colors.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await chat.blockPeer(conv.id);
                  if (mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _disappearLabel(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds == 3600) return '1 hour';
    if (seconds == 86400) return '1 day';
    if (seconds == 604800) return '7 days';
    if (seconds == 2592000) return '30 days';
    return '${seconds}s';
  }

  Future<void> _showDisappearSheet() async {
    final chat = context.read<ChatController>();
    final colors = context.read<ThemeController>().colors;
    const presets = <int>[0, 3600, 86400, 604800, 2592000];
    const labels = <String>['Off', '1 hour', '1 day', '7 days', '30 days'];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Disappearing messages',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (var i = 0; i < presets.length; i++)
              ListTile(
                leading: Icon(
                  presets[i] == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                  color: chat.disappearSeconds == presets[i] ? colors.accent : null,
                ),
                title: Text(labels[i]),
                trailing: chat.disappearSeconds == presets[i]
                    ? Icon(Icons.check_circle, color: colors.accent)
                    : null,
                onTap: () {
                  chat.setDisappearSeconds(presets[i]);
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(presets[i] == 0
                            ? 'Disappearing messages turned off'
                            : 'Messages will disappear after ${labels[i]}'),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;
    final scenic = theme.isFunTheme;
    final conv = chat.selected;
    if (conv == null) {
      return const Scaffold(body: Center(child: Text('No conversation')));
    }
    final typingName = chat.typingFrom == null ? null : chat.displayName(chat.typingFrom!);
    final visible = _visible(chat);

    // Sync composer when editing
    if (chat.editing != null && composer.text != (chat.editing!.text ?? '')) {
      // don't fight user typing mid-edit after first set — only when opening edit
    }

    final wpDeco = wallpaperDecoration(KeyStorage.instance.getWallpaper());

    return Scaffold(
      backgroundColor: scenic ? Colors.transparent : (wpDeco != null ? null : colors.chat),
      extendBodyBehindAppBar: scenic,
      appBar: AppBar(
        backgroundColor: scenic ? colors.surface.withValues(alpha: 0.52) : colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: searching
            ? TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search messages…',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              )
            : Row(
                children: [
                  GestureDetector(
                    onTap: conv.type == ConversationType.dm && !conv.isSelfChat
                        ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: conv.id)))
                        : null,
                    child: UserAvatar(
                      name: conv.title,
                      userId: conv.id,
                      hasAvatar: conv.peer?.hasAvatar == true || conv.group?.hasPhoto == true,
                      isGroup: conv.type == ConversationType.group,
                      online: conv.online,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(conv.title, overflow: TextOverflow.ellipsis)),
                            if (chat.disappearSeconds > 0) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.timer, size: 14, color: colors.accentCyan),
                              const SizedBox(width: 2),
                              Text(
                                _disappearLabel(chat.disappearSeconds),
                                style: TextStyle(color: colors.accentCyan, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          typingName != null
                              ? '$typingName is typing…'
                              : conv.type == ConversationType.group
                                  ? (conv.subtitle ?? 'Group')
                                  : (conv.peer?.statusText.isNotEmpty == true
                                      ? conv.peer!.statusText
                                      : conv.online
                                          ? 'online'
                                          : formatLastSeen(conv.peer?.lastLoginAt)),
                          style: TextStyle(
                            color: typingName != null ? colors.accentCyan : colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: searching ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                searching = !searching;
                if (!searching) {
                  searchQuery = '';
                  searchCtrl.clear();
                }
              });
            },
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'Options',
            onPressed: _chatOptions,
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: ThemeScene(
        themeId: theme.id,
        child: Container(
          decoration: wpDeco,
          child: Column(
          children: [
            if (scenic) SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
            if (chat.threadError != null)
              Material(
                color: colors.error.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(chat.threadError!, style: TextStyle(color: colors.error)),
                ),
              ),
            Builder(builder: (context) {
              final pinned = visible.where((m) => m.isPinned).toList();
              if (pinned.isEmpty) return const SizedBox.shrink();
              final latest = pinned.last;
              return Material(
                color: colors.elevated,
                child: InkWell(
                  onTap: () {
                    final idx = visible.indexOf(latest);
                    if (idx >= 0 && scroll.hasClients) {
                      scroll.animateTo(
                        idx * 80.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin, size: 16, color: colors.accentCyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            latest.text ?? '📎 Attachment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Expanded(
              child: chat.loadingThread
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            searchQuery.isNotEmpty
                                ? 'No matches'
                                : 'No messages yet. Say hello — it is sealed before it leaves this phone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final m = visible[i];
                            final mine = m.isMine(chat.me.id);
                            final showName = conv.type == ConversationType.group && !mine;
                            final showDateSep = _shouldShowDateSeparator(visible, i);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDateSep)
                                  _DateSeparator(date: m.createdAt!, colors: colors),
                                _MessageBubble(
                                  message: m,
                                  mine: mine,
                                  showName: showName,
                                  senderName: showName ? chat.displayName(m.from) : null,
                                  colors: colors,
                                  scenic: scenic,
                                  highlight: searchQuery.isNotEmpty,
                                  currentUserId: chat.me.id,
                                  onOpenActions: () => _messageActions(m),
                                  onVotePoll: (m.isPoll)
                                      ? (idx) => chat.voteOnPoll(m, idx)
                                      : null,
                                ),
                              ],
                            );
                          },
                        ),
            ),
            if (chat.replyTo != null || chat.editing != null)
              Container(
                width: double.infinity,
                color: colors.elevated.withValues(alpha: 0.9),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(chat.editing != null ? Icons.edit : Icons.reply, size: 18, color: colors.accentCyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chat.editing != null
                            ? 'Editing: ${chat.editing!.text ?? ''}'
                            : 'Replying to: ${chat.replyTo!.text ?? 'message'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        chat.clearComposerContext();
                        if (chat.editing == null) composer.clear();
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: scenic ? colors.surface.withValues(alpha: 0.62) : colors.surface,
                  border: Border(top: BorderSide(color: colors.border.withValues(alpha: scenic ? 0.45 : 1))),
                ),
                padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
                child: _recording
                    ? Row(
                        children: [
                          IconButton(
                            tooltip: 'Cancel',
                            onPressed: _cancelVoiceRecording,
                            icon: Icon(Icons.close, color: colors.error),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE11D48),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _fmtRecordTime(_recordSeconds),
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _recordSeconds >= _maxRecordSeconds - 5 ? 'Sending…' : 'Recording…',
                                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          CircleAvatar(
                            backgroundColor: colors.accent,
                            child: IconButton(
                              tooltip: 'Send voice note',
                              onPressed: chat.sending ? null : _stopAndSendVoice,
                              icon: Icon(Icons.send, color: colors.bubbleMineFg, size: 18),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          IconButton(
                            onPressed: chat.sending ? null : _attachSheet,
                            icon: Icon(Icons.add_circle_outline, color: colors.accent),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showEmojiPicker = !_showEmojiPicker;
                                if (_showEmojiPicker) {
                                  _composerFocus.unfocus();
                                } else {
                                  _composerFocus.requestFocus();
                                }
                              });
                            },
                            icon: Icon(
                              _showEmojiPicker ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                              color: colors.accent,
                            ),
                          ),
                          Expanded(
                            child: CompositedTransformTarget(
                              link: _composerLayerLink,
                              child: TextField(
                                controller: composer,
                                focusNode: _composerFocus,
                                minLines: 1,
                                maxLines: 5,
                                onChanged: (v) {
                                  _onComposerChangedWithMentions(v, chat);
                                  setState(() {});
                                },
                                onSubmitted: (_) => _send(),
                                onTap: () {
                                  _removeMentionOverlay();
                                  if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
                                },
                                decoration: InputDecoration(
                                  hintText: chat.editing != null ? 'Edit message…' : 'Encrypted message…',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          CircleAvatar(
                            backgroundColor: colors.accent,
                            child: IconButton(
                              tooltip: composer.text.trim().isEmpty && chat.editing == null
                                  ? 'Record voice note'
                                  : 'Send',
                              onPressed: chat.sending
                                  ? null
                                  : (composer.text.trim().isEmpty && chat.editing == null
                                      ? _startVoiceRecording
                                      : _send),
                              icon: chat.sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Icon(
                                      composer.text.trim().isEmpty && chat.editing == null
                                          ? Icons.mic
                                          : Icons.send,
                                      color: colors.bubbleMineFg,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (_showEmojiPicker && !_recording)
              EmojiPickerWidget(
                colors: colors,
                onEmojiSelected: (emoji) {
                  final text = composer.text;
                  final sel = composer.selection;
                  final int offset = sel.isValid ? sel.baseOffset : text.length;
                  final newText = text.substring(0, offset) + emoji + text.substring(offset);
                  composer.text = newText;
                  final newOffset = offset + emoji.length;
                  composer.selection = TextSelection.collapsed(offset: newOffset);
                },
              ),
          ],
        ),
        ),
      ),
    );
  }

  bool _shouldShowDateSeparator(List<ChatMessage> list, int index) {
    final current = list[index].createdAt;
    if (current == null) return false;
    if (index == 0) return true;
    final prev = list[index - 1].createdAt;
    if (prev == null) return true;
    return current.year != prev.year || current.month != prev.month || current.day != prev.day;
  }

  Future<void> _messageActions(ChatMessage message) async {
    final chat = context.read<ChatController>();
    final colors = context.read<ThemeController>().colors;
    final mine = message.isMine(chat.me.id);
    final isGroup = chat.selected?.type == ConversationType.group;
    final action = await showMessageActionsSheet(
      context: context,
      message: message,
      colors: colors,
      mine: mine,
      isGroup: isGroup,
    );
    if (action == null || !mounted) return;

    if (action.startsWith('react:')) {
      final ok = await chat.react(message, action.substring(6));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Reaction added' : (chat.threadError ?? 'Reaction failed'))),
        );
      }
    } else if (action == 'reply') {
      chat.setReplyTo(message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Replying — type your message below')),
        );
      }
    } else if (action == 'copy' && message.text != null) {
      await Clipboard.setData(ClipboardData(text: message.text!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
      }
    } else if (action == 'edit') {
      chat.setEditing(message);
      composer.text = message.text ?? '';
      composer.selection = TextSelection.collapsed(offset: composer.text.length);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Editing — change text and send')),
        );
      }
    } else if (action == 'delete_everyone') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete for everyone?'),
          content: const Text('This removes the message for all participants.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true && mounted) {
        await chat.deleteMessage(message, forEveryone: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message deleted')));
        }
      }
    } else if (action == 'delete_me') {
      await chat.deleteMessage(message, forEveryone: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from this device')));
      }
    } else if (action == 'info') {
      if (mounted) {
        showMessageInfoSheet(
          context: context,
          message: message,
          colors: colors,
          isGroup: isGroup,
        );
      }
    } else if (action == 'edit_history') {
      if (mounted) {
        showEditHistorySheet(
          context: context,
          message: message,
          colors: colors,
          chat: chat,
        );
      }
    } else if (action == 'forward') {
      if (!mounted) return;
      final ok = await showForwardSheet(context: context, message: message, colors: colors);
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message forwarded')),
        );
      }
    } else if (action == 'star') {
      // TODO: Backend has no star endpoint yet — toggling local state only.
      message.isStarred = !message.isStarred;
      chat.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.isStarred ? 'Message starred' : 'Star removed')),
        );
      }
    } else if (action == 'pin') {
      final conv = chat.selected;
      if (conv == null || conv.type != ConversationType.group) return;
      try {
        final api = context.read<ChatController>().auth.api;
        if (message.isPinned) {
          await api.unpinGroupMessage(conv.id, message.id);
          message.isPinned = false;
        } else {
          await api.pinGroupMessage(conv.id, message.id);
          message.isPinned = true;
        }
        chat.notify();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.isPinned ? 'Message pinned' : 'Message unpinned')),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pin failed: $e')),
          );
        }
      }
    }
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.colors});
  final DateTime date;
  final QcColors colors;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: colors.overlay.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.showName,
    required this.senderName,
    required this.colors,
    required this.scenic,
    required this.onOpenActions,
    required this.currentUserId,
    this.onVotePoll,
    this.highlight = false,
  });

  final ChatMessage message;
  final bool mine;
  final bool showName;
  final String? senderName;
  final QcColors colors;
  final bool scenic;
  final VoidCallback onOpenActions;
  final String currentUserId;
  final void Function(int optionIndex)? onVotePoll;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenActions,
          onLongPress: onOpenActions,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
              decoration: glassBubbleDecoration(mine: mine, colors: colors, scenic: scenic).copyWith(
                border: highlight
                    ? Border.all(color: colors.accentCyan, width: 1.5)
                    : glassBubbleDecoration(mine: mine, colors: colors, scenic: scenic).border,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (showName && senderName != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  senderName!,
                                  style: TextStyle(
                                    color: colors.accentCyan,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (message.forwardedFrom != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forward, size: 12, color: colors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Forwarded${message.forwardedFrom!.username != null ? ' from ${message.forwardedFrom!.username}' : ''}',
                                        style: TextStyle(color: colors.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (message.replyToText != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colors.overlay.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border(left: BorderSide(color: colors.accentCyan, width: 3)),
                                  ),
                                  child: Text(
                                    message.replyToText!,
                                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                                  ),
                                ),
                              ),
                            if (message.attachment != null && !message.viewOnce)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: AttachmentBubble(message: message, colors: colors),
                              ),
                            if (message.viewOnce)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _ViewOnceBubble(message: message, colors: colors),
                              ),
                            if (message.isPoll || message.isEvent || message.isAnnouncement)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: GroupMessageContent(
                                  message: message,
                                  colors: colors,
                                  currentUserId: currentUserId,
                                  onVotePoll: onVotePoll,
                                ),
                              )
                            else if (message.text != null && message.attachment == null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: LinkifiedText(
                                  text: message.text!,
                                  colors: colors,
                                  baseStyle: TextStyle(
                                    color: mine ? colors.bubbleMineFg : colors.bubbleTheirsFg,
                                    height: 1.35,
                                  ),
                                  mentionStyle: TextStyle(
                                    color: colors.accentCyan,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              )
                            else if (message.text == null && message.attachment == null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Unable to decrypt',
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: 'Message options',
                        onPressed: onOpenActions,
                        icon: Icon(Icons.more_vert, size: 18, color: colors.textMuted.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin, size: 12, color: colors.accentCyan),
                        ),
                      if (message.isStarred)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.star, size: 12, color: colors.accentCyan),
                        ),
                      if (message.isDisappearing)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.timer, size: 12, color: colors.accentCyan),
                        ),
                      if (message.editedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text('edited', style: TextStyle(color: colors.textMuted, fontSize: 10)),
                        ),
                      if (message.reactions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.overlay.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              message.reactions.map((r) => r.emoji).whereType<String>().join(' '),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      Text(
                        formatMessageTime(message.createdAt),
                        style: TextStyle(
                          color: mine ? colors.bubbleMineFg.withValues(alpha: 0.78) : colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.readAt != null
                              ? Icons.done_all
                              : message.deliveredAt != null
                                  ? Icons.done_all
                                  : Icons.done,
                          size: 14,
                          color: message.readAt != null
                              ? colors.accentCyan
                              : colors.bubbleMineFg.withValues(alpha: 0.78),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a view-once media placeholder or "opened" state.
class _ViewOnceBubble extends StatelessWidget {
  const _ViewOnceBubble({required this.message, required this.colors});

  final ChatMessage message;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    final opened = message.viewOnceOpenedAt != null;
    final mediaKind = message.viewOnceMediaKind ?? 'photo';
    final label = opened
        ? '${mediaKind[0].toUpperCase()}${mediaKind.substring(1)} opened'
        : 'View once $mediaKind';

    return GestureDetector(
      onTap: opened
          ? null
          : () async {
              final chat = context.read<ChatController>();
              final att = message.attachment;
              if (att != null) {
                final bytes = await chat.decryptAttachment(message);
                if (!context.mounted) return;
                if (bytes != null && att.isImage) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImageLightbox(
                        bytes: bytes,
                        filename: att.filename,
                        timestamp: message.createdAt,
                        colors: colors,
                      ),
                    ),
                  );
                }
              }
              if (!context.mounted) return;
              await chat.openViewOnce(message);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.overlay.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              opened ? Icons.visibility : Icons.visibility_off,
              size: 20,
              color: colors.accentCyan,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
