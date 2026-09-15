import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../crypto/key_storage.dart';
import '../models/models.dart';

class QuantumAiDonePayload {
  const QuantumAiDonePayload({
    required this.content,
    this.conversationId,
    this.contentHash,
    this.requestId,
    this.receipt,
    this.model,
  });

  final String content;
  final String? conversationId;
  final String? contentHash;
  final String? requestId;
  final String? receipt;
  final String? model;

  bool get hasSignedReceipt =>
      contentHash != null &&
      contentHash!.isNotEmpty &&
      requestId != null &&
      requestId!.isNotEmpty &&
      receipt != null &&
      receipt!.isNotEmpty;
}

/// SSE client for the QuantumAI companion service (website `aiClient.js` parity).
class QuantumAiClient {
  QuantumAiClient({required this.storage, String? baseUrl})
      : _overrideBase = baseUrl?.replaceAll(RegExp(r'/$'), '');

  final KeyStorage storage;
  final String? _overrideBase;
  http.Client? _activeClient;

  String get baseUrl =>
      (_overrideBase ?? storage.getAiApiBase() ?? AppConfig.defaultAiApiBase).replaceAll(RegExp(r'/$'), '');

  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }

  Map<String, String> _headers() {
    final token = storage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Streams a chat completion. Calls [onChunk] for each text fragment.
  Future<QuantumAiDonePayload> streamChat({
    required String message,
    String? conversationId,
    List<String>? context,
    Map<String, dynamic>? link,
    bool ephemeral = true,
    void Function(String conversationId)? onStart,
    void Function(String chunk)? onChunk,
  }) async {
    cancel();
    final client = http.Client();
    _activeClient = client;

    try {
      final uri = Uri.parse('$baseUrl/ai/chat');
      final request = http.Request('POST', uri)
        ..headers.addAll(_headers())
        ..body = jsonEncode({
          'message': message,
          if (conversationId != null && conversationId.isNotEmpty) 'conversationId': conversationId,
          if (context != null && context.isNotEmpty) 'explicitContext': context,
          if (link != null) 'sourceLink': link,
          'ephemeral': ephemeral,
          'stream': true,
        });

      final response = await client.send(request).timeout(const Duration(seconds: 90));
      if (response.statusCode >= 400) {
        final body = await response.stream.bytesToString();
        String err = 'QuantumAI request failed (${response.statusCode})';
        try {
          final parsed = jsonDecode(body);
          if (parsed is Map && parsed['error'] != null) err = '${parsed['error']}';
        } catch (_) {}
        throw ApiException(err, status: response.statusCode);
      }

      final buffer = StringBuffer();
      var pending = '';
      QuantumAiDonePayload? done;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pending += chunk;
        final parts = pending.split('\n\n');
        pending = parts.removeLast();
        for (final block in parts) {
          final trimmed = block.trim();
          if (trimmed.isEmpty) continue;
          final event = RegExp(r'^event:\s*(.+)$', multiLine: true).firstMatch(trimmed)?.group(1)?.trim();
          final raw = RegExp(r'^data:\s*(.+)$', multiLine: true).firstMatch(trimmed)?.group(1);
          if (raw == null) continue;
          Map<String, dynamic> data;
          try {
            data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } catch (_) {
            continue;
          }
          switch (event) {
            case 'start':
              final id = '${data['conversationId'] ?? ''}';
              if (id.isNotEmpty) onStart?.call(id);
            case 'chunk':
              final piece = '${data['content'] ?? ''}';
              if (piece.isNotEmpty) {
                buffer.write(piece);
                onChunk?.call(piece);
              }
            case 'done':
              final content = '${data['content'] ?? buffer.toString()}';
              done = QuantumAiDonePayload(
                content: content,
                conversationId: data['conversationId']?.toString(),
                contentHash: data['contentHash']?.toString(),
                requestId: data['requestId']?.toString(),
                receipt: data['receipt']?.toString(),
                model: data['model']?.toString(),
              );
            case 'error':
              throw ApiException('${data['message'] ?? 'QuantumAI stream failed'}');
          }
        }
      }

      if (done == null) {
        final text = buffer.toString().trim();
        if (text.isEmpty) throw ApiException('QuantumAI returned an empty response');
        done = QuantumAiDonePayload(content: text);
      }
      if (done.content.trim().isEmpty) {
        throw ApiException('QuantumAI returned an empty response');
      }
      return done;
    } on http.ClientException catch (e) {
      if (e.message.toLowerCase().contains('connection closed') ||
          e.message.toLowerCase().contains('client is closed')) {
        throw ApiException('Request cancelled.');
      }
      rethrow;
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }
}
