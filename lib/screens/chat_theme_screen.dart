import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';

class ChatThemeScreen extends StatefulWidget {
  const ChatThemeScreen({super.key, this.peerId, this.groupId});

  final String? peerId;
  final String? groupId;

  @override
  State<ChatThemeScreen> createState() => _ChatThemeScreenState();
}

class _ChatThemeScreenState extends State<ChatThemeScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> catalog = {};
  Map<String, dynamic> theme = {};
  bool saving = false;

  bool get _isGroup => widget.groupId != null && widget.groupId!.isNotEmpty;

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
      final cat = await api.fetchThemeCatalog();
      final t = _isGroup
          ? await api.fetchGroupChatTheme(widget.groupId!)
          : await api.fetchChatTheme(widget.peerId!);
      if (!mounted) return;
      setState(() {
        catalog = cat;
        theme = t;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save(Map<String, dynamic> payload) async {
    setState(() => saving = true);
    try {
      final api = context.read<AuthController>().api;
      final updated = _isGroup
          ? await api.saveGroupChatTheme(widget.groupId!, payload)
          : await api.saveChatTheme(widget.peerId!, payload);
      if (!mounted) return;
      setState(() => theme = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Theme saved')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() => saving = true);
    try {
      final api = context.read<AuthController>().api;
      final updated = _isGroup
          ? await api.resetGroupChatTheme(widget.groupId!)
          : await api.resetChatTheme(widget.peerId!);
      if (!mounted) return;
      setState(() => theme = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Theme reset')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Color _parseHex(String? hex, {Color fallback = const Color(0xFF6366F1)}) {
    if (hex == null || hex.isEmpty) return fallback;
    final cleaned = hex.replaceFirst('#', '');
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final presets = (catalog['presets'] as List<dynamic>? ?? []).cast<Map>();
    final bubbleColors = (catalog['bubbleColors'] as List<dynamic>? ?? []).cast<Map>();
    final wallpapers = (catalog['wallpapers'] as List<dynamic>? ?? []).cast<Map>();
    final selectedPreset = theme['presetId']?.toString();
    final selectedBubble = theme['bubbleColorId']?.toString() ?? 'default';
    final selectedWp = theme['wallpaperId']?.toString() ?? 'none';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat theme'),
        actions: [
          TextButton(
            onPressed: saving ? null : _reset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text('Presets', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: presets.map((p) {
                        final id = '${p['id']}';
                        final on = selectedPreset == id;
                        final bubbleId = '${p['bubbleColorId']}';
                        Map? bubble;
                        for (final b in bubbleColors) {
                          if ('${b['id']}' == bubbleId) {
                            bubble = b;
                            break;
                          }
                        }
                        return InkWell(
                          onTap: saving ? null : () => _save({'presetId': id}),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.elevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: on ? colors.accent : colors.border,
                                width: on ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _parseHex(bubble?['mine']?.toString()),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${p['name']}',
                                  style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Text('Bubble color', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: bubbleColors.map((b) {
                        final id = '${b['id']}';
                        final on = selectedBubble == id && selectedPreset == null;
                        return InkWell(
                          onTap: saving ? null : () => _save({'bubbleColorId': id}),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _parseHex(b['mine']?.toString()),
                              border: Border.all(
                                color: on ? colors.accentCyan : Colors.white24,
                                width: on ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Text('Wallpaper', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ...wallpapers.map((w) {
                      final id = '${w['id']}';
                      final on = selectedWp == id;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${w['name']}', style: TextStyle(color: colors.textPrimary)),
                        trailing: on ? Icon(Icons.check_circle, color: colors.accent) : null,
                        onTap: saving ? null : () => _save({'wallpaperId': id}),
                      );
                    }),
                    if (saving) ...[
                      const SizedBox(height: 16),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
    );
  }
}
