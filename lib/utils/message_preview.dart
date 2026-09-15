import 'dart:convert';

/// Parse sealed/system JSON message payloads (story reaction/reply, etc.).
Map<String, dynamic>? parseStructuredMessageText(String? text) {
  if (text == null) return null;
  final raw = text.trim();
  if (raw.length < 2 || !raw.startsWith('{') || !raw.endsWith('}')) return null;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map) return null;
    final type = parsed['type'] ?? parsed['__type'];
    if (type == null) return null;
    return Map<String, dynamic>.from(parsed);
  } catch (_) {
    return null;
  }
}

bool isStoryReactionPayload(Map<String, dynamic>? payload) =>
    payload != null && (payload['type'] == 'story_reaction' || payload['__type'] == 'story_reaction');

bool isStoryReplyPayload(Map<String, dynamic>? payload) =>
    payload != null && (payload['type'] == 'story_reply' || payload['__type'] == 'story_reply');

/// Human-readable preview — never show raw `{"type":"story_reaction",...}` in the UI.
String getMessagePreviewText(String? text, {bool isMine = false}) {
  final payload = parseStructuredMessageText(text);
  if (payload != null) {
    final type = '${payload['type'] ?? payload['__type'] ?? ''}';
    switch (type) {
      case 'story_reaction':
        final emoji = '${payload['emoji'] ?? ''}'.trim();
        if (isMine) {
          return emoji.isEmpty ? 'You reacted to their story' : '$emoji You reacted to their story';
        }
        return emoji.isEmpty ? 'Reacted to your story' : '$emoji Reacted to your story';
      case 'story_reply':
        final reply = '${payload['text'] ?? ''}'.trim();
        if (reply.isNotEmpty) return reply;
        return isMine ? 'You replied to their story' : 'Replied to your story';
    }
  }
  return text?.trim() ?? '';
}
