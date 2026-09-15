import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/key_storage.dart';
import '../crypto/qc_crypto.dart';
import '../models/models.dart';

Uint8List decodeFlexibleBase64(String b64) {
  var normalized = b64.replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s'), '');
  final pad = normalized.length % 4;
  if (pad == 2) normalized += '==';
  if (pad == 3) normalized += '=';
  return Uint8List.fromList(base64Decode(normalized));
}

/// AES-256-GCM decrypt matching website `aesGcmDecryptBytes` (WebCrypto).
Future<Uint8List> aesGcmDecryptBytes(Uint8List cipherWithTag, String keyB64, String ivB64) async {
  if (cipherWithTag.length < 17) {
    throw StateError('Ciphertext too short');
  }
  final keyBytes = decodeFlexibleBase64(keyB64);
  final iv = decodeFlexibleBase64(ivB64);
  final algorithm = AesGcm.with256bits();
  final secretKey = SecretKey(keyBytes);
  // WebCrypto packs ciphertext || 16-byte auth tag.
  final macBytes = cipherWithTag.sublist(cipherWithTag.length - 16);
  final cipherText = cipherWithTag.sublist(0, cipherWithTag.length - 16);
  final clear = await algorithm.decrypt(
    SecretBox(cipherText, nonce: iv, mac: Mac(macBytes)),
    secretKey: secretKey,
  );
  return Uint8List.fromList(clear);
}

Map<String, String>? _tryParseKeyPayload(String? text) {
  if (text == null || text.isEmpty) return null;
  try {
    final parsed = jsonDecode(text);
    if (parsed is Map && parsed['keyB64'] is String && parsed['ivB64'] is String) {
      return {
        'keyB64': parsed['keyB64'] as String,
        'ivB64': parsed['ivB64'] as String,
      };
    }
  } catch (_) {}
  return null;
}

/// Unlock AES media key from this viewer's sealed-story envelopes (website parity).
Future<({bool ok, Map<String, String>? payload, String? reason})> unlockStoryKey(
  StoryItem story,
  String currentUserId,
  KeyStorage storage,
) async {
  if (currentUserId.isEmpty) return (ok: false, payload: null, reason: 'no-user');
  final envelopes = story.envelopes.where((e) {
    final uid = e['user'];
    if (uid is Map) return '${uid['id'] ?? uid['_id'] ?? ''}' == currentUserId;
    return '$uid' == currentUserId;
  }).toList();
  if (envelopes.isEmpty) return (ok: false, payload: null, reason: 'no-envelope');

  final ring = await storage.getKeyring(currentUserId);

  for (final raw in envelopes) {
    SealedEnvelope envelope;
    try {
      envelope = SealedEnvelope.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      continue;
    }

    final hinted = await storage.findSecretKeyForPublicKey(currentUserId, envelope.targetPublicKey);
    if (hinted != null) {
      final payload = _tryParseKeyPayload(unsealMessage(envelope, hinted));
      if (payload != null) return (ok: true, payload: payload, reason: null);
    }

    for (final entry in ring) {
      if (hinted != null && entry.secretKey == hinted) continue;
      final payload = _tryParseKeyPayload(unsealMessage(envelope, entry.secretKey));
      if (payload != null) return (ok: true, payload: payload, reason: null);
    }
  }

  return (ok: false, payload: null, reason: 'no-secret');
}

bool looksLikeImageBytes(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // JPEG
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
  // PNG
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
  // GIF
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
  // WEBP (RIFF....WEBP)
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  return false;
}

/// Fetch story media and decrypt when sealed (website `resolveStoryMediaBlob`).
Future<Uint8List?> resolveStoryMediaBytes({
  required StoryItem story,
  required String currentUserId,
  required KeyStorage storage,
  required Future<Uint8List?> Function(String id) fetchRaw,
}) async {
  final raw = await fetchRaw(story.id);
  if (raw == null || raw.isEmpty) return null;

  if (!story.sealed) {
    if (looksLikeImageBytes(raw) || story.mediaType == 'video' || story.mediaType == 'audio') {
      return raw;
    }
    // Sometimes APIs return JSON error as bodyBytes with 200 — reject garbage.
    if (!looksLikeImageBytes(raw)) return null;
    return raw;
  }

  final unlocked = await unlockStoryKey(story, currentUserId, storage);
  final ivB64 = unlocked.payload?['ivB64'] ?? story.contentIv;
  final keyB64 = unlocked.payload?['keyB64'];
  if (!unlocked.ok || keyB64 == null || keyB64.isEmpty || ivB64 == null || ivB64.isEmpty) {
    throw StateError(
      unlocked.reason == 'no-envelope'
          ? 'This sealed story was not shared with your account'
          : 'Could not decrypt this sealed story (missing keys?)',
    );
  }

  final plain = await aesGcmDecryptBytes(raw, keyB64, ivB64);
  return plain;
}
