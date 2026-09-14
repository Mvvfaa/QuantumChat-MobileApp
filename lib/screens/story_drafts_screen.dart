import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';

class StoryDraftsScreen extends StatefulWidget {
  const StoryDraftsScreen({super.key});

  @override
  State<StoryDraftsScreen> createState() => _StoryDraftsScreenState();
}

class _StoryDraftsScreenState extends State<StoryDraftsScreen> {
  bool loading = true;
  String? error;
  List<StoryItem> items = [];

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
      final list = await context.read<AuthController>().api.listStoryDrafts();
      if (mounted) setState(() => items = list);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _publish(StoryItem s) async {
    try {
      final api = context.read<AuthController>().api;
      final chat = context.read<ChatController>();
      await api.publishStory(s.id);
      await chat.refreshStories();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story published')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(StoryItem s) async {
    try {
      await context.read<AuthController>().api.deleteStory(s.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Story drafts')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
              : items.isEmpty
                  ? Center(child: Text('No drafts or scheduled stories', style: TextStyle(color: colors.textMuted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(color: colors.border.withValues(alpha: 0.4)),
                      itemBuilder: (context, i) {
                        final s = items[i];
                        final when = s.publishAt ?? s.createdAt;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            s.caption.isNotEmpty ? s.caption : (s.isScheduled ? 'Scheduled story' : 'Draft'),
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${s.status}${when != null ? ' · ${when.toLocal()}' : ''}',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Publish now',
                                onPressed: () => _publish(s),
                                icon: Icon(Icons.publish_outlined, color: colors.accent),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _delete(s),
                                icon: Icon(Icons.delete_outline, color: colors.error),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
