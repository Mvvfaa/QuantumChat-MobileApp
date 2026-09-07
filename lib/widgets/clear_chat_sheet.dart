import 'package:flutter/material.dart';

import '../theme/qc_theme.dart';

const clearChatOptions = <(String, String)>[
  ('photo', 'Photos'),
  ('video', 'Videos'),
  ('voice', 'Voice notes'),
  ('document', 'Documents'),
  ('text', 'Text messages'),
  ('starred', 'Starred messages'),
];

/// Selective clear-chat sheet matching the website ClearChatModal.
Future<List<String>?> showClearChatSheet(BuildContext context, {required QcColors colors}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    builder: (ctx) => _ClearChatSheet(colors: colors),
  );
}

class _ClearChatSheet extends StatefulWidget {
  const _ClearChatSheet({required this.colors});
  final QcColors colors;

  @override
  State<_ClearChatSheet> createState() => _ClearChatSheetState();
}

class _ClearChatSheetState extends State<_ClearChatSheet> {
  final selected = <String>{};

  bool get allSelected => clearChatOptions.every((o) => selected.contains(o.$1));

  void toggleAll() {
    setState(() {
      if (allSelected) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..addAll(clearChatOptions.map((o) => o.$1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Clear this chat?',
              style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose what to remove from your view. This only affects your account.',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: allSelected,
              onChanged: (_) => toggleAll(),
              activeColor: colors.accent,
              title: Text('Select all', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            ...clearChatOptions.map(
              (opt) => CheckboxListTile(
                value: selected.contains(opt.$1),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      selected.add(opt.$1);
                    } else {
                      selected.remove(opt.$1);
                    }
                  });
                },
                activeColor: colors.accent,
                title: Text(opt.$2, style: TextStyle(color: colors.textPrimary)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (selected.contains('starred'))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Starred clear only empties your starred list — messages stay in the chat.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: colors.error),
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, selected.toList()),
                    child: const Text('Clear selected'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
