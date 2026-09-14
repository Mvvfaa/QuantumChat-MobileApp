import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../crypto/key_storage.dart';
import '../crypto/qc_crypto.dart';
import '../models/models.dart';

class ApiClient {
  ApiClient({required this.baseUrl, required this.storage});

  String baseUrl;
  final KeyStorage storage;

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$root$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = storage.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  dynamic _decode(http.Response res) {
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 400) {
      final error = body is Map ? (body['error'] as String? ?? 'Request failed') : 'Request failed';
      throw ApiException(error, status: res.statusCode);
    }
    if (body is Map && body['success'] == false) {
      throw ApiException(body['error'] as String? ?? 'Request failed', status: res.statusCode);
    }
    return body;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final res = await http.get(_uri(path, query), headers: _headers()).timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final res = await http
        .post(
          _uri(path),
          headers: _headers(),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    final res = await http.patch(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    final res = await http.put(
      _uri(path),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers());
    return _decode(res);
  }

  Future<Uint8List?> getBytes(String path) async {
    final res = await http.get(_uri(path), headers: _headers(json: false));
    if (res.statusCode >= 400) return null;
    return res.bodyBytes;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required List<String> publicKeys,
  }) async {
    final body = _decode(await http.post(
      _uri('/auth/register'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'publicKeys': publicKeys,
      }),
    ));
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceLabel,
    bool rememberMe = true,
  }) async {
    final body = _decode(await http.post(
      _uri('/auth/login'),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceLabel': deviceLabel,
        'rememberMe': rememberMe,
      }),
    ));
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verify2fa({
    required String tempToken,
    required String token,
    required String deviceLabel,
    bool rememberMe = true,
  }) async {
    final body = await post('/auth/2fa/verify', {
      'tempToken': tempToken,
      'token': token,
      'deviceLabel': deviceLabel,
      'rememberMe': rememberMe,
    });
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    final body = await get('/auth/me');
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final body = await post('/auth/forgot-password', {'email': email});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await post('/auth/reset-password', {'token': token, 'newPassword': newPassword});
  }

  Future<void> resendVerification() async {
    await post('/auth/resend-verification');
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await post('/auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<List<QcUser>> listUsers({String q = '', String? cursor}) async {
    final query = <String, String>{'limit': '100'};
    if (q.isNotEmpty) query['q'] = q;
    if (cursor != null) query['cursor'] = cursor;
    final body = await get('/users', query: query);
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => QcUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Loads every user page (for inbox) so friends aren't cut off by pagination.
  Future<List<QcUser>> listAllUsers({String q = ''}) async {
    final all = <QcUser>[];
    String? cursor;
    var guard = 0;
    while (guard < 50) {
      guard++;
      final query = <String, String>{'limit': '100'};
      if (q.isNotEmpty) query['q'] = q;
      if (cursor != null) query['cursor'] = cursor;
      final body = await get('/users', query: query);
      final data = body['data'] as List<dynamic>? ?? [];
      all.addAll(data.map((e) => QcUser.fromJson(e as Map<String, dynamic>)));
      final meta = body['meta'] as Map<String, dynamic>?;
      final hasMore = meta?['hasMore'] == true;
      final next = meta?['nextCursor']?.toString();
      if (!hasMore || next == null || next.isEmpty) break;
      cursor = next;
    }
    return all;
  }

  Future<QcUser> getUser(String id) async {
    final body = await get('/users/$id');
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getMyPublicKeys() async {
    final body = await get('/users/me/public-keys');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<QcUser> updatePublicKeys(List<String> publicKeys) async {
    final body = await patch('/users/me/public-keys', {'publicKeys': publicKeys});
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcUser> updateProfile(Map<String, dynamic> payload) async {
    final body = await patch('/users/me', payload);
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcUser> updatePrivacy(Map<String, dynamic> payload) async {
    final body = await patch('/users/me/privacy', payload);
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<QcUser>> listFriends() async {
    final body = await get('/users/friends');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => QcUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<FriendRequest>> friendRequestsIncoming() async {
    final body = await get('/users/friend-requests');
    final data = body['data'];
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = data['incoming'] as List<dynamic>? ?? [];
    }
    return list.map((e) => FriendRequest.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<Map<String, dynamic>>> friendRequests() async {
    final body = await get('/users/friend-requests');
    final data = body['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    if (data is Map) {
      return [
        ...(data['incoming'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      ];
    }
    return [];
  }

  Future<void> sendFriendRequest(String userId) async {
    await post('/users/friend-requests', {'to': userId});
  }

  Future<void> acceptFriendRequest(String id) async {
    await post('/users/friend-requests/$id/accept');
  }

  Future<void> declineFriendRequest(String id) async {
    await post('/users/friend-requests/$id/decline');
  }

  Future<Map<String, dynamic>?> lookupContact(String q) async {
    final body = await get('/users/lookup', query: {'q': q});
    return body['data'] as Map<String, dynamic>?;
  }

  Future<List<QcUser>> listBlocked() async {
    final body = await get('/users/me/blocked');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => QcUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> blockUser(String id) async => post('/users/$id/block');
  Future<void> unblockUser(String id) async => delete('/users/$id/block');

  Future<void> removeFriend(String userId) async => delete('/users/$userId/friend');

  Future<QcUser> muteChat({String? peerId, String? groupId, String duration = 'always'}) async {
    final body = await post('/users/me/mute', {
      if (peerId != null) 'peerId': peerId,
      if (groupId != null) 'groupId': groupId,
      'duration': duration,
    });
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcUser> unmuteChat({String? peerId, String? groupId}) async {
    final body = await post('/users/me/unmute', {
      if (peerId != null) 'peerId': peerId,
      if (groupId != null) 'groupId': groupId,
    });
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> clearChat({
    String? peerId,
    String? groupId,
    List<String> scopes = const ['all'],
  }) async {
    await post('/users/me/clear-chat', {
      if (peerId != null) 'peerId': peerId,
      if (groupId != null) 'groupId': groupId,
      'scopes': scopes,
    });
  }

  /// Empty [restoreEntries] = full undo of clear watermarks for that chat.
  Future<Map<String, dynamic>> undoClearChat({
    String? peerId,
    String? groupId,
    List<dynamic> restoreEntries = const [],
  }) async {
    final body = await post('/users/me/clear-chat/undo', {
      if (peerId != null) 'peerId': peerId,
      if (groupId != null) 'groupId': groupId,
      'restoreEntries': restoreEntries,
    });
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<QcUser> uploadAvatar(Uint8List bytes, {String filename = 'avatar.jpg', String mime = 'image/jpeg'}) async {
    final request = http.MultipartRequest('POST', _uri('/users/me/avatar'));
    request.headers.addAll(_headers(json: false));
    request.files.add(http.MultipartFile.fromBytes('avatar', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return QcUser.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAvatar() async => delete('/users/me/avatar');

  Future<Map<String, dynamic>> setup2fa() async {
    final body = await post('/auth/2fa/setup');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<QcUser> enable2fa(String token) async {
    final body = await post('/auth/2fa/enable', {'token': token});
    final data = body['data'] as Map<String, dynamic>;
    return QcUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<QcUser> disable2fa({required String password, required String token}) async {
    final body = await post('/auth/2fa/disable', {'password': password, 'token': token});
    final data = body['data'] as Map<String, dynamic>;
    return QcUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<QcGroup>> listGroups({String q = ''}) async {
    final query = <String, String>{'limit': '50'};
    if (q.isNotEmpty) query['q'] = q;
    final body = await get('/groups', query: query);
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => QcGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<QcGroup> getGroup(String id) async {
    final body = await get('/groups/$id');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup> createGroup({
    required String name,
    String description = '',
    List<String> memberIds = const [],
    String visibility = 'private',
    String? joinPolicy,
  }) async {
    final body = await post('/groups', {
      'name': name,
      'description': description,
      'memberIds': memberIds,
      'visibility': visibility,
      if (visibility == 'public') 'joinPolicy': joinPolicy == 'request' ? 'request' : 'open',
    });
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup> addGroupMembers(String groupId, List<String> memberIds) async {
    final body = await post('/groups/$groupId/members', {'memberIds': memberIds});
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup?> removeGroupMember(String groupId, String memberId) async {
    final body = await delete('/groups/$groupId/members/$memberId');
    final data = body['data'];
    if (data is Map && data['deleted'] == true) return null;
    return QcGroup.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> leaveGroup(String groupId, String myId) async {
    await delete('/groups/$groupId/members/$myId');
  }

  Future<QcGroup> setGroupInvite({
    required String groupId,
    bool enabled = true,
    bool rotate = false,
  }) async {
    final body = await post('/groups/$groupId/invite', {
      'enabled': enabled,
      'rotate': rotate,
    });
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteGroup(String groupId) async {
    await delete('/groups/$groupId');
  }

  Future<List<Map<String, dynamic>>> getConversation(String userId, {String? before}) async {
    final query = <String, String>{'limit': '50'};
    if (before != null) query['before'] = before;
    final body = await get('/messages/$userId', query: query);
    return (body['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> payload) async {
    final body = await post('/messages', payload);
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> editMessage(String id, Map<String, dynamic> payload) async {
    final body = await patch('/messages/$id', payload);
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> deleteMessage(String id, {bool forEveryone = false}) async {
    final res = await http.delete(
      _uri('/messages/$id').replace(queryParameters: {
        if (forEveryone) 'forEveryone': 'true',
      }),
      headers: _headers(),
    );
    _decode(res);
  }

  Future<Map<String, dynamic>> getMessageInfo(String id) async {
    final body = await get('/messages/$id/info');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> markRead(String userId) async {
    await post('/messages/$userId/read');
  }

  Future<Map<String, dynamic>> reactToMessage(String id, Map<String, dynamic> payload) async {
    final body = await post('/messages/$id/reactions', payload);
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(String groupId, {String? before}) async {
    final query = <String, String>{'limit': '50'};
    if (before != null) query['before'] = before;
    final body = await get('/groups/$groupId/messages', query: query);
    return (body['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendGroupMessage(String groupId, Map<String, dynamic> payload) async {
    final body = await post('/groups/$groupId/messages', payload);
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> votePoll(String messageId, int optionIndex) async {
    final body = await post('/groups/messages/$messageId/poll-vote', {
      'optionIndex': optionIndex,
    });
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> syncMessages({String? since}) async {
    final query = <String, String>{};
    if (since != null) query['since'] = since;
    final body = await get('/messages/sync', query: query);
    return (body['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchGifs(String q) async {
    final body = await get('/gifs/search', query: {'q': q});
    final data = body['data'];
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['results'] is List) {
      return (data['results'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<StoryItem>> listStories() async {
    final body = await get('/stories');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => StoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<StoryItem> createStory({
    required Uint8List bytes,
    required String filename,
    String mimetype = 'image/jpeg',
    String mediaType = 'image',
    String status = 'published',
    String? publishAt,
    String? caption,
    int? ttlMs,
    bool allowReplies = true,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/stories'));
    request.headers.addAll(_headers(json: false));
    request.fields['sealed'] = 'false';
    request.fields['mediaType'] = mediaType;
    request.fields['mimetype'] = mimetype;
    request.fields['status'] = status;
    request.fields['allowReplies'] = allowReplies ? 'true' : 'false';
    if (publishAt != null && publishAt.isNotEmpty) request.fields['publishAt'] = publishAt;
    if (caption != null && caption.isNotEmpty) request.fields['caption'] = caption;
    if (ttlMs != null) request.fields['ttlMs'] = '$ttlMs';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return StoryItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Uint8List?> getStoryMedia(String id) async => getBytes('/stories/$id/media');

  Future<void> markStoryViewed(String id) async => post('/stories/$id/view');

  Future<void> deleteStory(String id) async => delete('/stories/$id');

  Future<void> reactToStory(String id, String emoji) async {
    await post('/stories/$id/react', {'emoji': emoji});
  }

  Future<List<StoryItem>> listStoryDrafts() async {
    final body = await get('/stories/mine/drafts');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => StoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<StoryItem>> listStoryArchive() async {
    final body = await get('/stories/mine/archive');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => StoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<StoryItem> publishStory(String id) async {
    final body = await post('/stories/$id/publish');
    return StoryItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<StoryItem> updateStory(String id, Map<String, dynamic> payload) async {
    final body = await patch('/stories/$id', payload);
    return StoryItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> getStoryViewers(String id) async {
    final body = await get('/stories/$id/viewers');
    final data = body['data'];
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['viewers'] is List) {
      return (data['viewers'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<StoryItem> reshareStory(String id) async {
    final body = await post('/stories/$id/reshare');
    return StoryItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  // ── Chat themes ──

  Future<Map<String, dynamic>> fetchThemeCatalog() async {
    final body = await get('/chat-themes/presets');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> fetchChatTheme(String peerId) async {
    final body = await get('/chat-themes/$peerId');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> saveChatTheme(String peerId, Map<String, dynamic> payload) async {
    final body = await put('/chat-themes/$peerId', payload);
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> resetChatTheme(String peerId) async {
    final body = await delete('/chat-themes/$peerId');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> fetchGroupChatTheme(String groupId) async {
    final body = await get('/chat-themes/group/$groupId');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> saveGroupChatTheme(String groupId, Map<String, dynamic> payload) async {
    final body = await put('/chat-themes/group/$groupId', payload);
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> resetGroupChatTheme(String groupId) async {
    final body = await delete('/chat-themes/group/$groupId');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  // ── Highlights ──

  Future<List<HighlightItem>> listHighlights({String? userId}) async {
    final query = <String, String>{};
    if (userId != null && userId.isNotEmpty) query['userId'] = userId;
    final body = await get('/highlights', query: query.isEmpty ? null : query);
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => HighlightItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<HighlightItem> createHighlight({required String name}) async {
    final request = http.MultipartRequest('POST', _uri('/highlights'));
    request.headers.addAll(_headers(json: false));
    request.fields['name'] = name;
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return HighlightItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Backend requires a media file; [sourceStoryId] is optional metadata.
  Future<HighlightItem> addHighlightItem({
    required String highlightId,
    required Uint8List bytes,
    required String filename,
    String mimetype = 'image/jpeg',
    String? sourceStoryId,
    String? caption,
    String? mediaType,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/highlights/$highlightId/items'));
    request.headers.addAll(_headers(json: false));
    if (sourceStoryId != null) request.fields['sourceStoryId'] = sourceStoryId;
    if (caption != null) request.fields['caption'] = caption;
    if (mediaType != null) request.fields['mediaType'] = mediaType;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return HighlightItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteHighlight(String id) async => delete('/highlights/$id');

  Future<Uint8List?> getHighlightCover(String id) async => getBytes('/highlights/$id/cover');

  // ── Device link ──

  Future<Map<String, dynamic>> createDeviceLinkRequest() async {
    final body = await post('/users/me/sessions/link');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> approveDeviceLink(String linkId) async {
    final body = await post('/users/me/sessions/link/approve', {'linkId': linkId});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> rejectDeviceLink(String linkId) async {
    final body = await post('/users/me/sessions/link/reject', {'linkId': linkId});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> sendDeviceLinkEmail({required String linkId, required String token}) async {
    final body = await post('/users/me/sessions/link/email', {'linkId': linkId, 'token': token});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Unauthenticated — new device verifying a scanned QR.
  Future<Map<String, dynamic>> verifyDeviceLink({
    required String linkId,
    required String token,
    String deviceLabel = 'Mobile',
  }) async {
    final body = await post('/users/sessions/link/verify', {
      'linkId': linkId,
      'token': token,
      'deviceLabel': deviceLabel,
      'deviceInfo': {'userAgent': 'QuantumChat Flutter', 'label': deviceLabel},
    });
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> pollDeviceLinkStatus({
    required String linkId,
    required String token,
  }) async {
    final body = await post('/users/sessions/link/status', {'linkId': linkId, 'token': token});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> claimDeviceLinkSession({
    required String linkId,
    required String token,
  }) async {
    final body = await post('/users/sessions/link/claim', {'linkId': linkId, 'token': token});
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Init → put bytes → finalize (website-compatible attachment upload).
  Future<Map<String, dynamic>> uploadDmAttachment({
    required String recipientId,
    required String filename,
    required String mimetype,
    required SealedFileBytes forRecipient,
    required SealedFileBytes forSender,
  }) async {
    final init = await post('/attachments/init', {
      'recipientId': recipientId,
      'filename': filename,
      'mimetype': mimetype,
      'size': forRecipient.cipherBytes.length,
      'nonce': forRecipient.nonce,
      'ephemeralPublicKey': forRecipient.ephemeralPublicKey,
      'targetPublicKey': forRecipient.targetPublicKey,
      'forSenderNonce': forSender.nonce,
      'forSenderEphemeralPublicKey': forSender.ephemeralPublicKey,
      'forSenderTargetPublicKey': forSender.targetPublicKey,
    });
    final data = init['data'] as Map<String, dynamic>;
    final pendingUploadId = '${data['pendingUploadId']}';
    await _putAttachmentBytes(pendingUploadId, 'recipient', forRecipient.cipherBytes, filename);
    await _putAttachmentBytes(pendingUploadId, 'sender', forSender.cipherBytes, filename);
    final finalized = await post('/attachments/finalize', {'pendingUploadId': pendingUploadId});
    return finalized['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadGroupAttachment({
    required String groupId,
    required String filename,
    required String mimetype,
    required SecretBoxSealed sealed,
  }) async {
    final init = await post('/attachments/init', {
      'groupId': groupId,
      'secretboxNonce': sealed.nonce,
      'filename': filename,
      'mimetype': mimetype,
      'size': sealed.cipherBytes.length,
    });
    final data = init['data'] as Map<String, dynamic>;
    final pendingUploadId = '${data['pendingUploadId']}';
    await _putAttachmentBytes(pendingUploadId, 'recipient', sealed.cipherBytes, filename);
    final finalized = await post('/attachments/finalize', {'pendingUploadId': pendingUploadId});
    return finalized['data'] as Map<String, dynamic>;
  }

  Future<void> _putAttachmentBytes(
    String pendingUploadId,
    String slot,
    Uint8List bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest(
      'PUT',
      _uri('/attachments/pending/$pendingUploadId/bytes', {'slot': slot}),
    );
    request.headers.addAll(_headers(json: false));
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _decode(res);
  }

  Future<Uint8List?> downloadAttachmentRaw(String id) async => getBytes('/attachments/$id/raw');

  /// Open a view-once message (atomic claim).
  Future<Map<String, dynamic>> openViewOnce(String messageId) async {
    final body = await post('/messages/$messageId/view-once');
    return body['data'] as Map<String, dynamic>;
  }

  /// Check if a message can be forwarded.
  Future<Map<String, dynamic>> checkForwardAllowed(String messageId) async {
    final body = await get('/messages/$messageId/forward-check');
    return body['data'] as Map<String, dynamic>;
  }

  /// Pin a message in a group.
  Future<void> pinGroupMessage(String groupId, String messageId) async {
    await post('/groups/$groupId/pins/$messageId');
  }

  /// Unpin a message in a group.
  Future<void> unpinGroupMessage(String groupId, String messageId) async {
    await delete('/groups/$groupId/pins/$messageId');
  }

  // TODO: Backend does not have star/unstar endpoints yet.
  // These are placeholders for when the backend adds them.
  // Future<void> starMessage(String messageId) async {
  //   await post('/messages/$messageId/star');
  // }
  // Future<void> unstarMessage(String messageId) async {
  //   await delete('/messages/$messageId/star');
  // }

  Future<void> markViewOnceOpened(String messageId) async {
    await post('/messages/$messageId/view-once');
  }

  String avatarUrl(String userId) => '${baseUrl.replaceAll(RegExp(r'/$'), '')}/users/$userId/avatar';

  // ── Group management ──

  Future<QcGroup> updateGroup(String groupId, Map<String, dynamic> payload) async {
    final body = await patch('/groups/$groupId', payload);
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup> uploadGroupPhoto(String groupId, Uint8List bytes, {String filename = 'photo.jpg', String mime = 'image/jpeg'}) async {
    final request = http.MultipartRequest('POST', _uri('/groups/$groupId/photo'));
    request.headers.addAll(_headers(json: false));
    request.files.add(http.MultipartFile.fromBytes('photo', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup> promoteAdmin(String groupId, String memberId) async {
    final body = await post('/groups/$groupId/admins/$memberId');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<QcGroup> demoteAdmin(String groupId, String memberId) async {
    final body = await delete('/groups/$groupId/admins/$memberId');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  // ── Notification settings ──

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final body = await get('/users/me/notification-settings');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updateNotificationSettings(Map<String, dynamic> settings) async {
    final body = await put('/users/me/notification-settings', settings);
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  // ── Sessions ──

  Future<List<Map<String, dynamic>>> listSessions() async {
    final body = await get('/users/me/sessions');
    return (body['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> revokeSession(String sessionId) async {
    await delete('/users/me/sessions/$sessionId');
  }

  // ── Language ──

  Future<void> updateLanguage(String languageCode) async {
    await patch('/users/me/language', {'language': languageCode});
  }

  // ── Reports ──

  Future<void> reportUser({required String userId, required String reason, String details = ''}) async {
    await post('/reports', {'userId': userId, 'reason': reason, 'details': details});
  }

  // ── Group invites ──

  Future<Map<String, dynamic>> previewInvite(String code) async {
    final body = await get('/groups/invite/${code.trim().toLowerCase()}');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<QcGroup> joinViaInvite(String code) async {
    final normalized = code.trim().toLowerCase();
    final body = await post('/groups/join/$normalized');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  // ── Discover / public join ──

  Future<List<DiscoverGroup>> discoverGroups({String q = ''}) async {
    final query = <String, String>{'limit': '30'};
    if (q.isNotEmpty) query['q'] = q;
    final body = await get('/groups/discover', query: query);
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => DiscoverGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<QcGroup> joinPublicGroup(String groupId) async {
    final body = await post('/groups/$groupId/join');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createJoinRequest(String groupId) async {
    final body = await post('/groups/$groupId/join-requests');
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<List<GroupJoinRequest>> listJoinRequests(String groupId) async {
    final body = await get('/groups/$groupId/join-requests');
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((e) => GroupJoinRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<QcGroup> acceptJoinRequest(String groupId, String userId) async {
    final body = await post('/groups/$groupId/join-requests/$userId/accept');
    return QcGroup.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> rejectJoinRequest(String groupId, String userId) async {
    await post('/groups/$groupId/join-requests/$userId/reject');
  }
}
