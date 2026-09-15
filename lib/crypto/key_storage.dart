import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'qc_crypto.dart';

const _tokenKey = 'qc_token';
const _userKey = 'qc_user';
const _sessionIdKey = 'qc_session_id';
const _apiBaseKey = 'qc_api_base';
const _aiApiBaseKey = 'qc_ai_api_base';
const _themeKey = 'qc_theme';
const _appIconKey = 'qc_app_icon';
const _rememberEmailKey = 'qc_remember_email';
const _keyringPrefix = 'qc_keyring_';
const _readPrefix = 'qc_read_';
const _activityPrefix = 'qc_activity_';
const _wallpaperKey = 'qc_wallpaper';
const _languageKey = 'qc_language';
const _archivePrefix = 'qc_archived_chats_';
const _hiddenPrefix = 'qc_hidden_chats_';

class KeyringEntry {
  const KeyringEntry({
    required this.publicKey,
    required this.secretKey,
    required this.createdAt,
  });

  final String publicKey;
  final String secretKey;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'secretKey': secretKey,
        'createdAt': createdAt,
      };

  factory KeyringEntry.fromJson(Map<String, dynamic> json) => KeyringEntry(
        publicKey: (json['publicKey'] as String).toLowerCase(),
        secretKey: json['secretKey'] as String,
        createdAt: json['createdAt'] as int? ?? 0,
      );
}

class ConversationActivity {
  const ConversationActivity({required this.at, this.from});
  final String at;
  final String? from;
}

class KeyStorage {
  KeyStorage._();
  static final KeyStorage instance = KeyStorage._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) {
      throw StateError('KeyStorage.init() must run before use');
    }
    return p;
  }

  Future<List<KeyringEntry>> getKeyring(String userId) async {
    final raw = await _secure.read(key: _keyringPrefix + userId);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => KeyringEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addKeySetToRing(String userId, List<KeyPairHex> keyPairs) async {
    final ring = await getKeyring(userId);
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    ring.addAll(
      keyPairs.map(
        (k) => KeyringEntry(
          publicKey: k.publicKey.toLowerCase(),
          secretKey: k.secretKey,
          createdAt: createdAt,
        ),
      ),
    );
    await _secure.write(key: _keyringPrefix + userId, value: jsonEncode(ring.map((e) => e.toJson()).toList()));
  }

  Future<List<KeyringEntry>> getCurrentKeySet(String userId, [int size = keySetSize]) async {
    final ring = await getKeyring(userId);
    if (ring.length <= size) return ring;
    return ring.sublist(ring.length - size);
  }

  Future<String?> findSecretKeyForPublicKey(String userId, String? publicKeyHex) async {
    if (publicKeyHex == null || publicKeyHex.isEmpty) return null;
    final target = publicKeyHex.toLowerCase();
    final ring = await getKeyring(userId);
    for (final k in ring) {
      if (k.publicKey == target) return k.secretKey;
    }
    return null;
  }

  Future<bool> hasKeyring(String userId) async {
    return (await getKeyring(userId)).isNotEmpty;
  }

  Future<bool> keyringMatchesPublishedKeys(String userId, List<String> serverPublicKeys) async {
    final serverKeys = serverPublicKeys.map((k) => k.toLowerCase()).where((k) => k.isNotEmpty).toList();
    if (serverKeys.isEmpty) return false;
    for (final pub in serverKeys) {
      if (await findSecretKeyForPublicKey(userId, pub) == null) return false;
    }
    return true;
  }

  Future<void> clearKeyring(String userId) async {
    await _secure.delete(key: _keyringPrefix + userId);
  }

  Future<void> saveSession(String token, Map<String, dynamic> user, [String? sessionId]) async {
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
    if (sessionId != null) {
      await prefs.setString(_sessionIdKey, sessionId);
    }
  }

  String? getToken() => prefs.getString(_tokenKey);

  String? getSessionId() => prefs.getString(_sessionIdKey);

  Map<String, dynamic>? getStoredUser() {
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      final user = jsonDecode(raw) as Map<String, dynamic>;
      if (user['id'] == null) {
        clearSession();
        return null;
      }
      return user;
    } catch (_) {
      clearSession();
      return null;
    }
  }

  void clearSession() {
    prefs.remove(_tokenKey);
    prefs.remove(_userKey);
    prefs.remove(_sessionIdKey);
  }

  String? getApiBase() => prefs.getString(_apiBaseKey);
  Future<void> setApiBase(String url) => prefs.setString(_apiBaseKey, url.replaceAll(RegExp(r'/$'), ''));

  String? getAiApiBase() => prefs.getString(_aiApiBaseKey);
  Future<void> setAiApiBase(String url) => prefs.setString(_aiApiBaseKey, url.replaceAll(RegExp(r'/$'), ''));
  Future<void> clearAiApiBase() => prefs.remove(_aiApiBaseKey);

  String? getThemeId() => prefs.getString(_themeKey);
  Future<void> setThemeId(String id) => prefs.setString(_themeKey, id);

  String? getAppIconId() => prefs.getString(_appIconKey);
  Future<void> setAppIconId(String id) => prefs.setString(_appIconKey, id);

  String? getWallpaper() => prefs.getString(_wallpaperKey);
  Future<void> setWallpaper(String value) => prefs.setString(_wallpaperKey, value);
  Future<void> clearWallpaper() => prefs.remove(_wallpaperKey);

  String? getLanguage() => prefs.getString(_languageKey);
  Future<void> setLanguage(String code) => prefs.setString(_languageKey, code);

  String? getRememberedEmail() => prefs.getString(_rememberEmailKey);
  Future<void> setRememberedEmail(String? email) async {
    if (email == null || email.isEmpty) {
      await prefs.remove(_rememberEmailKey);
    } else {
      await prefs.setString(_rememberEmailKey, email);
    }
  }

  String conversationKeyForUser(String peerId) => 'dm:$peerId';
  String conversationKeyForGroup(String groupId) => 'group:$groupId';

  String? getLastReadAt(String userId, String conversationKey) {
    return prefs.getString('$_readPrefix${userId}_$conversationKey');
  }

  Future<void> markConversationRead(String userId, String conversationKey) {
    return prefs.setString(
      '$_readPrefix${userId}_$conversationKey',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> setConversationActivity(
    String userId,
    String conversationKey, {
    required String at,
    String? from,
  }) {
    return prefs.setString(
      '$_activityPrefix${userId}_$conversationKey',
      jsonEncode({'at': at, 'from': from}),
    );
  }

  ConversationActivity? getConversationActivity(String userId, String conversationKey) {
    final raw = prefs.getString('$_activityPrefix${userId}_$conversationKey');
    if (raw == null) return null;
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final at = parsed['at'] as String?;
      if (at == null) return null;
      return ConversationActivity(at: at, from: parsed['from'] as String?);
    } catch (_) {
      return null;
    }
  }

  bool isUnread(String userId, String conversationKey, String? activityAt, String? activityFrom) {
    if (activityAt == null) return false;
    if (activityFrom != null && activityFrom == userId) return false;
    final lastRead = getLastReadAt(userId, conversationKey);
    if (lastRead == null) return true;
    return activityAt.compareTo(lastRead) > 0;
  }

  List<String> _readStringList(String prefix, String userId) {
    final raw = prefs.getString('$prefix$userId');
    if (raw == null) return [];
    try {
      final parsed = jsonDecode(raw) as List<dynamic>;
      return parsed.map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _writeStringList(String prefix, String userId, List<String> list) async {
    await prefs.setString('$prefix$userId', jsonEncode(list));
    return list;
  }

  List<String> getArchivedChatKeys(String userId) => _readStringList(_archivePrefix, userId);

  bool isChatArchived(String userId, String conversationKey) {
    return getArchivedChatKeys(userId).contains(conversationKey);
  }

  Future<List<String>> toggleArchiveChat(String userId, String conversationKey) async {
    final current = getArchivedChatKeys(userId);
    if (current.contains(conversationKey)) {
      return _writeStringList(_archivePrefix, userId, current.where((k) => k != conversationKey).toList());
    }
    return _writeStringList(_archivePrefix, userId, [...current, conversationKey]);
  }

  List<String> getHiddenChatIds(String userId) => _readStringList(_hiddenPrefix, userId);

  Future<List<String>> hideChat(String userId, String peerId) async {
    final next = {...getHiddenChatIds(userId), peerId};
    return _writeStringList(_hiddenPrefix, userId, next.toList());
  }

  Future<List<String>> unhideChat(String userId, String peerId) async {
    return _writeStringList(
      _hiddenPrefix,
      userId,
      getHiddenChatIds(userId).where((id) => id != peerId).toList(),
    );
  }
}
