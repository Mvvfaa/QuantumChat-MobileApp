import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/ai_client.dart';
import '../api/qc_socket.dart';
import '../crypto/key_storage.dart';
import '../crypto/qc_crypto.dart';
import '../models/models.dart';
import '../utils/display_name.dart';
import '../utils/group_payload.dart';
import '../widgets/avatar_cache.dart';
import 'auth_controller.dart';

class ChatController extends ChangeNotifier {
  ChatController({required this.auth, required this.storage, required this.socket}) {
    auth.onSocketConnected = _onSocketReady;
    socket.addConnectListener(_onSocketReady);
    _ai = QuantumAiClient(storage: storage);
  }

  final AuthController auth;
  final KeyStorage storage;
  final QcSocket socket;
  late final QuantumAiClient _ai;

  List<QcUser> users = [];
  List<QcUser> friends = [];
  List<QcGroup> groups = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  List<FriendRequest> friendRequests = [];
  List<StoryItem> stories = [];
  Conversation? selected;
  ChatMessage? replyTo;
  ChatMessage? editing;
  String filter = 'all';
  String search = '';
  bool loadingInbox = false;
  bool loadingThread = false;
  bool sending = false;
  bool aiBusy = false;
  String? threadError;
  String? typingFrom;
  /// Per-conversation disappearing-message TTL in seconds (0 = off).
  int disappearSeconds = 0;
    final Set<String> onlineUserIds = {};
  int incomingRequestCount = 0;
  Timer? _typingDebounce;
  Timer? _pollTimer;
  Timer? _threadPollTimer;
  String? _joinedGroupId;
  bool _started = false;
  bool _handlersRegistered = false;
  String? _lastThreadSyncAt;
  int _openGeneration = 0;
  bool _threadRefreshInFlight = false;
  bool _pollSyncInFlight = false;
  bool _inboxRefreshInFlight = false;

  QcUser get me => auth.user!;

  /// Public notify for external callers (e.g. star/pin toggle from UI).
  void notify() => notifyListeners();

  Future<void> start() async {
    auth.onSocketConnected = _onSocketReady;
    _ensureSocketHandlers();
    _started = true;
    await refreshInbox();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (auth.user == null) return;
      if (!socket.connected) {
        unawaited(_pollSync());
      }
    });
    _threadPollTimer?.cancel();
    _threadPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (auth.user == null || selected == null) return;
      unawaited(refreshOpenThread());
    });
  }

  void stop() {
    _started = false;
    _pollTimer?.cancel();
    _threadPollTimer?.cancel();
    _typingDebounce?.cancel();
    cancelQuantumAi();
    _removeSocketHandlers();
  }

  void _onSocketReady() {
    if (!_started) return;
    _rejoinOpenGroup();
  }

  void _rejoinOpenGroup() {
    final conv = selected;
    if (conv?.type != ConversationType.group) return;
    socket.joinGroup(conv!.id);
    _joinedGroupId = conv.id;
  }

  void _ensureSocketHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;
    socket.on('message:new', _handleMessageNew);
    socket.on('message:status', _handleMessageStatus);
    socket.on('message:poll', _handleMessagePoll);
    socket.on('presence:snapshot', _handlePresenceSnapshot);
    socket.on('presence:update', _handlePresenceUpdate);
    socket.on('typing:start', _handleTypingStart);
    socket.on('typing:stop', _handleTypingStop);
    socket.on('friend:request:new', _handleFriendRequestNew);
    socket.on('friend:request:accepted', _handleFriendRequestAccepted);
    socket.on('message:view-once-opened', _handleViewOnceOpened);
  }

  void _removeSocketHandlers() {
    if (!_handlersRegistered) return;
    _handlersRegistered = false;
    socket.off('message:new', _handleMessageNew);
    socket.off('message:status', _handleMessageStatus);
    socket.off('message:poll', _handleMessagePoll);
    socket.off('presence:snapshot', _handlePresenceSnapshot);
    socket.off('presence:update', _handlePresenceUpdate);
    socket.off('typing:start', _handleTypingStart);
    socket.off('typing:stop', _handleTypingStop);
    socket.off('friend:request:new', _handleFriendRequestNew);
    socket.off('friend:request:accepted', _handleFriendRequestAccepted);
    socket.off('message:view-once-opened', _handleViewOnceOpened);
  }

  Future<void> _handleMessageNew(dynamic raw) async {
    try {
      await _ingestRawMessage(raw);
    } catch (e, st) {
      debugPrint('message:new handler failed: $e\n$st');
    }
  }

  Future<void> _handleMessagePoll(dynamic raw) async {
    try {
      if (raw is! Map) return;
      final map = _coerceMap(raw);
      final id = _messageId(map);
      if (id.isEmpty) return;
      final conv = selected;
      if (conv == null || !_rawBelongsToConversation(map, conv)) return;
      final updated = await decorate(map);
      messages = messages.map((m) => m.id == id ? updated : m).toList();
      notifyListeners();
    } catch (e, st) {
      debugPrint('message:poll handler failed: $e\n$st');
    }
  }

  void _handleMessageStatus(dynamic raw) {
    if (raw is! Map) return;
    final id = '${raw['id']}';
    messages = messages.map((m) {
      if (m.id != id) return m;
      m.deliveredAt = _parseDate(raw['deliveredAt']) ?? m.deliveredAt;
      m.readAt = _parseDate(raw['readAt']) ?? m.readAt;
      return m;
    }).toList();
    notifyListeners();
  }

  void _handlePresenceSnapshot(dynamic raw) {
    onlineUserIds
      ..clear()
      ..addAll(((raw is Map ? raw['onlineUserIds'] : null) as List<dynamic>? ?? []).map((e) => '$e'));
    _rebuildConversations();
  }

  void _handlePresenceUpdate(dynamic raw) {
    if (raw is! Map) return;
    final id = '${raw['userId']}';
    if (raw['online'] == true) {
      onlineUserIds.add(id);
    } else {
      onlineUserIds.remove(id);
    }
    _rebuildConversations();
  }

  void _handleTypingStart(dynamic raw) {
    if (raw is! Map || selected == null) return;
    final from = _normalizeUserId(raw['from']) ?? '';
    if (from == me.id) return;
    final groupId = _normalizeUserId(raw['groupId']);
    if (selected!.type == ConversationType.group) {
      if (groupId == selected!.id) typingFrom = from;
    } else if (from == selected!.id) {
      typingFrom = from;
    }
    notifyListeners();
  }

  void _handleTypingStop(dynamic raw) {
    if (raw is! Map) return;
    final from = _normalizeUserId(raw['from']) ?? '';
    if (from == typingFrom) {
      typingFrom = null;
      notifyListeners();
    }
  }

  void _handleFriendRequestNew(dynamic _) {
    unawaited(_refreshFriendRequests());
  }

  void _handleFriendRequestAccepted(dynamic _) {
    unawaited(refreshInbox());
  }

  void _handleViewOnceOpened(dynamic raw) {
    if (raw is! Map) return;
    final id = '${raw['id'] ?? raw['_id']}';
    messages = messages.map((m) {
      if (m.id != id) return m;
      m.viewOnce = true;
      m.viewOnceOpenedAt = _parseDate(raw['viewOnceOpenedAt']) ?? DateTime.now();
      m.viewOnceOpenedBy = _normalizeUserId(raw['viewOnceOpenedBy']);
      m.viewOnceMediaKind = raw['viewOnceMediaKind'] as String? ?? m.viewOnceMediaKind;
      m.attachment = null;
      return m;
    }).toList();
    notifyListeners();
  }

  Future<void> _refreshFriendRequests() async {
    try {
      friendRequests = await auth.api.friendRequestsIncoming();
      incomingRequestCount = friendRequests.length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshStories() async {
    try {
      stories = await auth.api.listStories();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> acceptFriendRequest(String id) async {
    await auth.api.acceptFriendRequest(id);
    await refreshInbox();
  }

  Future<void> declineFriendRequest(String id) async {
    await auth.api.declineFriendRequest(id);
    await _refreshFriendRequests();
  }

  Future<void> blockPeer(String userId) async {
    await auth.api.blockUser(userId);
    await refreshInbox();
  }

  Future<void> muteSelected({String duration = 'always'}) async {
    final conv = selected;
    if (conv == null) return;
    if (conv.type == ConversationType.dm) {
      await auth.api.muteChat(peerId: conv.id, duration: duration);
    } else {
      await auth.api.muteChat(groupId: conv.id, duration: duration);
    }
    conv.muted = true;
    notifyListeners();
  }

  Future<void> unmuteSelected() async {
    final conv = selected;
    if (conv == null) return;
    if (conv.type == ConversationType.dm) {
      await auth.api.unmuteChat(peerId: conv.id);
    } else {
      await auth.api.unmuteChat(groupId: conv.id);
    }
    conv.muted = false;
    notifyListeners();
  }

  /// Returns true when a server clear ran (UI can offer undo).
  Future<bool> clearSelectedChat({List<String> scopes = const ['all']}) async {
    final conv = selected;
    if (conv == null) return false;
    final clearingStarred = scopes.contains('starred');
    var serverScopes = scopes.where((s) => s != 'starred').toList();

    if (serverScopes.isEmpty && clearingStarred) {
      for (final m in messages) {
        m.isStarred = false;
      }
      notifyListeners();
      return false;
    }

    if (scopes.contains('all') ||
        ({'photo', 'video', 'voice', 'document', 'text'}.difference(serverScopes.toSet()).isEmpty)) {
      serverScopes = ['all'];
    }
    if (serverScopes.isEmpty) serverScopes = ['all'];

    if (conv.type == ConversationType.dm) {
      await auth.api.clearChat(peerId: conv.id, scopes: serverScopes);
    } else {
      await auth.api.clearChat(groupId: conv.id, scopes: serverScopes);
    }

    if (serverScopes.contains('all')) {
      messages = [];
    } else {
      messages = messages.where((m) => !serverScopes.any(m.matchesClearScope)).toList();
    }
    if (clearingStarred) {
      for (final m in messages) {
        m.isStarred = false;
      }
    }
    notifyListeners();
    return true;
  }

  Future<void> undoClearSelectedChat() async {
    final conv = selected;
    if (conv == null) return;
    if (conv.type == ConversationType.dm) {
      await auth.api.undoClearChat(peerId: conv.id, restoreEntries: const []);
    } else {
      await auth.api.undoClearChat(groupId: conv.id, restoreEntries: const []);
    }
    await refreshOpenThread();
  }

  Future<void> toggleArchiveSelected() async {
    final conv = selected;
    if (conv == null) return;
    await storage.toggleArchiveChat(me.id, conv.key);
    conv.archived = !conv.archived;
    _rebuildConversations();
  }

  Future<void> hideSelectedChat() async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.dm || conv.isSelfChat) return;
    await storage.hideChat(me.id, conv.id);
    closeThread();
    _rebuildConversations();
  }

  Future<QcGroup> joinGroupViaInvite(String code) async {
    final group = await auth.api.joinViaInvite(code.trim().toLowerCase());
    await refreshInbox();
    return group;
  }

  void setReplyTo(ChatMessage? message) {
    replyTo = message;
    editing = null;
    notifyListeners();
  }

  void setEditing(ChatMessage? message) {
    editing = message;
    replyTo = null;
    notifyListeners();
  }

  void clearComposerContext() {
    replyTo = null;
    editing = null;
    notifyListeners();
  }

  void setDisappearSeconds(int seconds) {
    disappearSeconds = seconds;
    notifyListeners();
  }

  Future<void> refreshInbox() async {
    if (!auth.hasLocalKeyring) return;
    if (_inboxRefreshInFlight) return;
    _inboxRefreshInFlight = true;
    loadingInbox = true;
    notifyListeners();
    try {
      users = await auth.api.listAllUsers();
      groups = await auth.api.listGroups();
      try {
        friends = await auth.api.listFriends();
      } catch (_) {
        friends = [];
      }
      _mergeFriendProfiles();
      for (final u in users) {
        if (u.hasAvatar) AvatarCache.instance.bust(u.id);
      }
      await _refreshFriendRequests();
      await refreshStories();
      await _ensureQuantumAiContact();
      _rebuildConversations();
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
    } finally {
      loadingInbox = false;
      _inboxRefreshInFlight = false;
      notifyListeners();
    }
  }

  void _mergeFriendProfiles() {
    if (friends.isEmpty) return;
    final friendById = {for (final f in friends) f.id: f};
    final merged = users.map((u) {
      final f = friendById[u.id];
      if (f == null) return u;
      return u.copyWith(
        displayName: f.displayName.isNotEmpty ? f.displayName : u.displayName,
        hasAvatar: u.hasAvatar || f.hasAvatar,
      );
    }).toList();
    final ids = merged.map((u) => u.id).toSet();
    for (final f in friends) {
      if (!ids.contains(f.id)) merged.add(f);
    }
    users = merged;
  }

  /// Prefer pinning the seeded QuantumAI system user in the inbox when discoverable.
  Future<void> _ensureQuantumAiContact() async {
    final existing = await resolveQuantumAiUser(forceNetwork: users.every((u) => !u.isQuantumAi));
    if (existing == null) return;
    if (!users.any((u) => u.id == existing.id)) {
      users = [existing, ...users];
    }
  }

  /// Find the QuantumAI system user (cached list first, then search).
  Future<QcUser?> resolveQuantumAiUser({bool forceNetwork = false}) async {
    for (final u in users) {
      if (u.isQuantumAi) return u;
    }
    if (!forceNetwork && users.isNotEmpty) {
      // Still try network once when missing — list may omit system users.
    }
    try {
      final found = await auth.api.listUsers(q: 'QuantumAI');
      for (final u in found) {
        if (u.isQuantumAi || u.username.toLowerCase() == 'quantumai') {
          if (!users.any((x) => x.id == u.id)) {
            users = [u, ...users];
          }
          return u;
        }
      }
      // Broader scan of first pages if username search is empty.
      final all = await auth.api.listUsers(q: 'quantum');
      for (final u in all) {
        if (u.isQuantumAi) {
          if (!users.any((x) => x.id == u.id)) {
            users = [u, ...users];
          }
          return u;
        }
      }
    } catch (e) {
      debugPrint('resolveQuantumAiUser failed: $e');
    }
    return null;
  }

  /// Open (or prepare) the QuantumAI DM and return its conversation.
  Future<Conversation> openQuantumAiChat() async {
    final ai = await resolveQuantumAiUser(forceNetwork: true);
    if (ai == null) {
      throw ApiException(
        'QuantumAI is not available on this server. Ask an admin to seed the QuantumAI system user.',
      );
    }
    if (!users.any((u) => u.id == ai.id)) {
      users = [ai, ...users];
    }
    _rebuildConversations();
    Conversation? conv;
    for (final c in conversations) {
      if (c.type == ConversationType.dm && c.id == ai.id) {
        conv = c;
        break;
      }
    }
    conv ??= Conversation(
      key: storage.conversationKeyForUser(ai.id),
      type: ConversationType.dm,
      id: ai.id,
      title: ai.title.isNotEmpty ? ai.title : 'QuantumAI',
      subtitle: 'Your sealed AI companion',
      peer: ai,
      sortAt: DateTime.now().toUtc().toIso8601String(),
    );
    unawaited(open(conv));
    return conv;
  }

  Future<void> searchPeople(String q) async {
    search = q;
    if (q.trim().length < 2) {
      // Filter locally — do not reload every user page on each keystroke clear.
      _rebuildConversations();
      return;
    }
    try {
      users = await auth.api.listUsers(q: q.trim());
      groups = await auth.api.listGroups(q: q.trim());
      _rebuildConversations();
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
    }
  }

  void setFilter(String next) {
    filter = next;
    _rebuildConversations();
  }

  void _rebuildConversations() {
    final items = <Conversation>[];
    final self = Conversation(
      key: storage.conversationKeyForUser(me.id),
      type: ConversationType.dm,
      id: me.id,
      title: 'Message yourself',
      subtitle: 'Notes to self',
      peer: me,
      isSelfChat: true,
      sortAt: storage.getConversationActivity(me.id, storage.conversationKeyForUser(me.id))?.at ?? '',
    );
    self.unread = storage.isUnread(me.id, self.key, self.sortAt.isEmpty ? null : self.sortAt, null);
    self.archived = storage.isChatArchived(me.id, self.key);
    items.add(self);

    for (final u in users) {
      if (u.id == me.id) continue;
      final key = storage.conversationKeyForUser(u.id);
      final activity = storage.getConversationActivity(me.id, key);
      items.add(Conversation(
        key: key,
        type: ConversationType.dm,
        id: u.id,
        title: u.title,
        peer: u,
        unread: storage.isUnread(me.id, key, activity?.at, activity?.from),
        sortAt: activity?.at ?? u.lastLoginAt?.toIso8601String() ?? '',
        online: onlineUserIds.contains(u.id) && u.privacy.online != 'nobody',
        archived: storage.isChatArchived(me.id, key),
      ));
    }
    for (final g in groups) {
      final key = storage.conversationKeyForGroup(g.id);
      final activity = storage.getConversationActivity(me.id, key);
      final count = g.members.length;
      items.add(Conversation(
        key: key,
        type: ConversationType.group,
        id: g.id,
        title: g.name,
        subtitle: g.description.isNotEmpty
            ? g.description
            : '$count member${count == 1 ? '' : 's'}',
        group: g,
        unread: storage.isUnread(me.id, key, activity?.at, activity?.from),
        sortAt: activity?.at ?? g.updatedAt?.toIso8601String() ?? '',
        archived: storage.isChatArchived(me.id, key),
      ));
    }

    items.sort((a, b) {
      if (a.isSelfChat != b.isSelfChat) return a.isSelfChat ? -1 : 1;
      final aAi = a.peer?.isQuantumAi == true;
      final bAi = b.peer?.isQuantumAi == true;
      if (aAi != bAi) return aAi ? -1 : 1;
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      return b.sortAt.compareTo(a.sortAt);
    });

    final q = search.trim().toLowerCase();
    final hidden = storage.getHiddenChatIds(me.id).toSet();
    conversations = items.where((c) {
      if (c.type == ConversationType.dm && !c.isSelfChat && q.isEmpty && hidden.contains(c.id)) {
        return false;
      }
      if (filter == 'archived') {
        if (!c.archived) return false;
      } else if (c.archived) {
        return false;
      }
      if (filter == 'groups' && c.type != ConversationType.group) return false;
      if (filter == 'unread' && !c.unread) return false;
      if (filter == 'friends') {
        if (c.isSelfChat) return true;
        if (c.type != ConversationType.dm) return false;
        return friends.any((f) => f.id == c.id);
      }
      if (q.isNotEmpty && !c.title.toLowerCase().contains(q) && !(c.subtitle ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    notifyListeners();
  }

  Future<void> open(Conversation conv) async {
    final openToken = ++_openGeneration;
    if (_joinedGroupId != null && _joinedGroupId != conv.id) {
      socket.leaveGroup(_joinedGroupId!);
      _joinedGroupId = null;
    }
    selected = conv;
    typingFrom = null;
    disappearSeconds = 0;
    messages = [];
    _lastThreadSyncAt = null;
    loadingThread = true;
    threadError = null;
    notifyListeners();
    if (conv.type == ConversationType.group) {
      socket.joinGroup(conv.id);
      _joinedGroupId = conv.id;
    }
    try {
      final raw = conv.type == ConversationType.dm
          ? await auth.api.getConversation(conv.id)
          : await auth.api.getGroupMessages(conv.id);
      if (openToken != _openGeneration || selected?.key != conv.key) return;

      final decorated = <ChatMessage>[];
      for (final row in raw) {
        if (openToken != _openGeneration || selected?.key != conv.key) return;
        decorated.add(await decorate(row));
        // Yield so taps/scroll stay responsive while decrypting a long history.
        if (decorated.length % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (openToken != _openGeneration || selected?.key != conv.key) return;

      messages = decorated;
      await storage.markConversationRead(me.id, conv.key);
      conv.unread = false;
      if (conv.type == ConversationType.dm) {
        unawaited(auth.api.markRead(conv.id));
      }
      for (final m in messages.where((m) => !m.isMine(me.id))) {
        socket.markDelivered(m.id);
      }
      _lastThreadSyncAt = DateTime.now().toUtc().toIso8601String();
      _rebuildConversations();
    } on ApiException catch (e) {
      if (openToken == _openGeneration) threadError = e.message;
    } finally {
      if (openToken == _openGeneration) {
        loadingThread = false;
        notifyListeners();
      }
    }
  }

  void closeThread() {
    _openGeneration++;
    if (_joinedGroupId != null) {
      socket.leaveGroup(_joinedGroupId!);
      _joinedGroupId = null;
    }
    selected = null;
    messages = [];
    _lastThreadSyncAt = null;
    typingFrom = null;
    loadingThread = false;
    notifyListeners();
  }

  Future<ChatMessage> decorate(Map<String, dynamic> raw) async {
    final from = _normalizeUserId(raw['from']) ?? '';
    final isMine = from == me.id;
    String? text;
    Map<String, dynamic>? groupFileMeta;
    if (raw['group'] != null && raw['content'] is String && (raw['content'] as String).isNotEmpty) {
      text = raw['content'] as String;
    } else if (raw['group'] != null && raw['envelopes'] is List) {
      final envelopes = (raw['envelopes'] as List).whereType<Map>();
      Map<String, dynamic>? mineEnv;
      for (final e in envelopes) {
        if ('${e['user']}' == me.id) mineEnv = Map<String, dynamic>.from(e);
      }
      if (mineEnv != null) {
        try {
          final env = SealedEnvelope.fromJson(mineEnv);
          final sk = await storage.findSecretKeyForPublicKey(me.id, env.targetPublicKey);
          text = sk == null ? null : unsealMessage(env, sk);
        } catch (_) {
          text = null;
        }
      }
    } else {
      final envelopeJson = isMine ? raw['forSender'] : raw['forRecipient'];
      if (envelopeJson is Map) {
        try {
          final env = SealedEnvelope.fromJson(Map<String, dynamic>.from(envelopeJson));
          final sk = await storage.findSecretKeyForPublicKey(me.id, env.targetPublicKey);
          text = sk == null ? null : unsealMessage(env, sk);
        } catch (_) {
          text = null;
        }
      }
    }

    PollData? pollData;
    EventData? eventData;
    String? announcementBody;
    if (text != null && text.trim().startsWith('{')) {
      try {
        final obj = jsonDecode(text) as Map<String, dynamic>;
        if (obj['__qc'] == 1) {
          final type = obj['type'] as String?;
          if (type == 'announcement') {
            announcementBody = obj['body'] as String? ?? '';
            text = announcementBody;
          } else if (type == 'text') {
            text = obj['body'] as String? ?? text;
          } else if (type == 'file') {
            text = obj['filename'] as String? ?? 'File';
            groupFileMeta = obj;
          } else if (type == 'poll') {
            pollData = PollData.fromPayload(obj);
            text = pollData.question;
          } else if (type == 'event') {
            eventData = EventData.fromPayload(obj);
            text = eventData.title;
          }
        }
      } catch (_) {}
    }

    final reactions = <Reaction>[];
    for (final r in (raw['reactions'] as List<dynamic>? ?? [])) {
      if (r is! Map) continue;
      if (r['emoji'] != null && r['forRecipient'] == null && r['forSender'] == null) {
        reactions.add(Reaction(userId: '${r['user']}', emoji: r['emoji'] as String?));
        continue;
      }
      final mineReaction = '${r['user']}' == me.id;
      final envJson = mineReaction ? r['forSender'] : r['forRecipient'];
      if (envJson is! Map) {
        reactions.add(Reaction(userId: '${r['user']}'));
        continue;
      }
      try {
        final env = SealedEnvelope.fromJson(Map<String, dynamic>.from(envJson));
        final sk = await storage.findSecretKeyForPublicKey(me.id, env.targetPublicKey);
        reactions.add(Reaction(userId: '${r['user']}', emoji: sk == null ? null : unsealMessage(env, sk)));
      } catch (_) {
        reactions.add(Reaction(userId: '${r['user']}'));
      }
    }

    AttachmentMeta? attachment;
    final attRaw = raw['attachment'];
    if (attRaw is Map) {
      attachment = AttachmentMeta.fromJson(
        Map<String, dynamic>.from(attRaw),
        groupKey: groupFileMeta?['key'] as String?,
        groupNonce: groupFileMeta?['nonce'] as String?,
      );
      if (text == null || text.isEmpty) {
        text = attachment.filename;
      }
    } else if (groupFileMeta != null && groupFileMeta['attachmentId'] != null) {
      attachment = AttachmentMeta(
        id: '${groupFileMeta['attachmentId']}',
        filename: groupFileMeta['filename'] as String? ?? 'file',
        mimetype: groupFileMeta['mimetype'] as String? ?? 'application/octet-stream',
        size: (groupFileMeta['size'] as num?)?.toInt() ?? 0,
        encryption: 'secretbox',
        groupKey: groupFileMeta['key'] as String?,
        groupNonce: groupFileMeta['nonce'] as String?,
        secretboxNonce: groupFileMeta['nonce'] as String?,
      );
    }

    String? replyToId;
    String? replyToText;
    final replyRaw = raw['replyTo'];
    if (replyRaw is Map) {
      replyToId = '${replyRaw['id'] ?? replyRaw['_id']}';
      replyToText = 'Reply';
    } else if (replyRaw != null) {
      replyToId = '$replyRaw';
      replyToText = 'Reply';
    }

    ForwardedFromMeta? forwardedFrom;
    final fwdRaw = raw['forwardedFrom'];
    if (fwdRaw is Map) {
      forwardedFrom = ForwardedFromMeta.fromJson(Map<String, dynamic>.from(fwdRaw));
    }

    final editHistory = <EditHistoryEntry>[];
    final rawHistory = raw['editHistory'] as List<dynamic>?;
    if (rawHistory != null) {
      for (final h in rawHistory) {
        if (h is! Map) continue;
        final editedAt = _parseDate(h['editedAt']);
        if (editedAt == null) continue;
        String? histText;
        if (h['content'] is String && (h['content'] as String).isNotEmpty) {
          histText = h['content'] as String;
        } else if (raw['group'] != null && h['envelopes'] is List) {
          final envs = (h['envelopes'] as List).whereType<Map>();
          Map<String, dynamic>? mineEnv;
          for (final e in envs) {
            if ('${e['user']}' == me.id) mineEnv = Map<String, dynamic>.from(e);
          }
          if (mineEnv != null) {
            try {
              final env = SealedEnvelope.fromJson(mineEnv);
              final sk = await storage.findSecretKeyForPublicKey(me.id, env.targetPublicKey);
              histText = sk == null ? null : unsealMessage(env, sk);
            } catch (_) {}
          }
        } else {
          final envJson = isMine ? h['forSender'] : h['forRecipient'];
          if (envJson is Map) {
            try {
              final env = SealedEnvelope.fromJson(Map<String, dynamic>.from(envJson));
              final sk = await storage.findSecretKeyForPublicKey(me.id, env.targetPublicKey);
              histText = sk == null ? null : unsealMessage(env, sk);
            } catch (_) {}
          }
        }
        if (histText != null && histText.trim().startsWith('{')) {
          try {
            final obj = jsonDecode(histText) as Map<String, dynamic>;
            if (obj['__qc'] == 1 && (obj['type'] == 'text' || obj['type'] == 'announcement')) {
              histText = obj['body'] as String? ?? histText;
            }
          } catch (_) {}
        }
        editHistory.add(EditHistoryEntry(editedAt: editedAt, text: histText));
      }
    }

    final mentionedUserIds = (raw['mentionedUserIds'] as List<dynamic>? ?? [])
        .map((e) => '$e')
        .toList();

    final pollVotes = <PollVote>[];
    for (final v in (raw['pollVotes'] as List<dynamic>? ?? [])) {
      if (v is Map) {
        pollVotes.add(PollVote.fromJson(Map<String, dynamic>.from(v)));
      }
    }

    final kind = raw['kind'] as String? ?? (attachment != null ? 'file' : 'text');
    // Prefer kind from server; fall back to payload type when kind is missing.
    final resolvedKind = kind != 'text'
        ? kind
        : pollData != null
            ? 'poll'
            : eventData != null
                ? 'event'
                : announcementBody != null
                    ? 'announcement'
                    : kind;

    return ChatMessage(
      // Normalize IDs (string vs {$oid: ...} shapes) so optimistic + socket payloads dedupe correctly.
      id: _messageId(raw),
      from: from,
      to: _normalizeUserId(raw['to']),
      groupId: _normalizeUserId(raw['group']),
      text: text,
      createdAt: _parseDate(raw['createdAt']),
      deliveredAt: _parseDate(raw['deliveredAt']),
      readAt: _parseDate(raw['readAt']),
      editedAt: _parseDate(raw['editedAt']),
      expiresAt: _parseDate(raw['expiresAt']),
      reactions: reactions,
      replyToId: replyToId,
      replyToText: replyToText,
      kind: resolvedKind,
      attachment: attachment,
      forwardedFrom: forwardedFrom,
      editHistory: editHistory,
      viewOnce: raw['viewOnce'] == true,
      viewOnceOpenedAt: _parseDate(raw['viewOnceOpenedAt']),
      viewOnceOpenedBy: _normalizeUserId(raw['viewOnceOpenedBy']),
      viewOnceMediaKind: raw['viewOnceMediaKind'] as String?,
      mentionedUserIds: mentionedUserIds,
      pollData: pollData,
      pollVotes: pollVotes,
      eventData: eventData,
      announcementBody: announcementBody,
      mediaCategory: raw['mediaCategory'] as String?,
      quantumAI: resolvedKind == 'ai' || resolvedKind == 'ai_note',
    );
  }

  bool get selectedIsQuantumAi {
    final peer = selected?.peer;
    if (peer != null) return peer.isQuantumAi;
    final id = selected?.id;
    if (id == null) return false;
    for (final u in users) {
      if (u.id == id) return u.isQuantumAi;
    }
    return false;
  }

  void cancelQuantumAi() {
    _ai.cancel();
    aiBusy = false;
    var changed = false;
    for (final m in messages) {
      if (!m.streaming) continue;
      m.streaming = false;
      m.failed = true;
      if ((m.text ?? '').trim().isEmpty) m.text = 'Request cancelled.';
      changed = true;
    }
    if (changed) messages = [...messages];
    notifyListeners();
  }

  Future<void> sendPrivateQuantumAIMessage(String text) async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.dm) {
      throw ApiException('QuantumAI DMs only');
    }
    if (aiBusy) throw ApiException('QuantumAI is already responding');
    threadError = null;
    final peer = conv.peer ??
        users.cast<QcUser?>().firstWhere((u) => u?.id == conv.id, orElse: () => null);
    if (peer == null || !peer.isQuantumAi) {
      throw ApiException('This chat is not QuantumAI');
    }
    if (peer.publicKeys.isEmpty) {
      throw ApiException('Missing QuantumAI encryption keys');
    }
    final mySet = await storage.getCurrentKeySet(me.id);
    if (mySet.isEmpty) {
      throw ApiException('Missing your encryption keys');
    }

    final forRecipient = sealMessage(text, pickRandom(peer.publicKeys));
    final forSender = sealMessage(text, pickRandom(mySet.map((k) => k.publicKey).toList()));
    final rawPrompt = await auth.api.sendMessage({
      'to': conv.id,
      'forRecipient': forRecipient.toJson(),
      'forSender': forSender.toJson(),
    });
    final promptMsg = await decorate(rawPrompt);
    promptMsg.text = text;
    messages = [...messages, promptMsg];
    notifyListeners();

    final assistantId = 'quantum-ai-assistant-${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = ChatMessage(
      id: assistantId,
      from: peer.id,
      to: me.id,
      text: '',
      createdAt: DateTime.now().toUtc(),
      kind: 'ai',
      quantumAI: true,
      streaming: true,
      pending: true,
    );
    messages = [...messages, placeholder];
    aiBusy = true;
    notifyListeners();

    try {
      final recentContext = messages
          .where((m) => m.id != assistantId && (m.text ?? '').trim().isNotEmpty)
          .toList()
          .reversed
          .take(20)
          .toList()
          .reversed
          .map((m) {
        final who = m.isMine(me.id) ? 'User' : 'QuantumAI';
        return '$who: ${m.text}';
      }).toList();

      final done = await _ai.streamChat(
        message: text,
        context: recentContext,
        link: {'quantumChatPeerId': me.id},
        ephemeral: true,
        onChunk: (chunk) {
          final idx = messages.indexWhere((m) => m.id == assistantId);
          if (idx < 0) return;
          final current = messages[idx];
          current.text = '${current.text ?? ''}$chunk';
          messages = [...messages];
          notifyListeners();
        },
      );

      if (done.hasSignedReceipt) {
        try {
          final stored = await auth.api.publishQuantumAiResponse(
            content: done.content,
            contentHash: done.contentHash!,
            requestId: done.requestId!,
            receipt: done.receipt!,
            model: done.model,
          );
          final sealed = await decorate(stored);
          sealed.quantumAI = true;
          sealed.kind = 'ai';
          messages = [
            for (final m in messages)
              if (m.id == assistantId) sealed else m,
          ];
        } on ApiException catch (e) {
          // Stream OK but receipt publish failed — keep visible reply.
          debugPrint('QuantumAI receipt publish failed: ${e.message}');
          final idx = messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            messages[idx].text = done.content;
            messages[idx].streaming = false;
            messages[idx].kind = 'ai';
            messages[idx].quantumAI = true;
            messages = [...messages];
          }
          threadError =
              'QuantumAI replied, but the answer was not sealed into history (${e.message})';
        }
      } else {
        final idx = messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0) {
          messages[idx].text = done.content;
          messages[idx].streaming = false;
          messages[idx].kind = 'ai';
          messages[idx].quantumAI = true;
          messages = [...messages];
        }
        threadError =
            'QuantumAI replied, but QUANTUM_AI_SERVICE_SECRET is missing/mismatched — reply was not sealed into chat history';
      }

      await storage.setConversationActivity(
        me.id,
        conv.key,
        at: DateTime.now().toUtc().toIso8601String(),
        from: peer.id,
      );
      _rebuildConversations();
    } catch (e) {
      final idx = messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        final existing = (messages[idx].text ?? '').trim();
        messages[idx].text = existing.isNotEmpty
            ? existing
            : (e is ApiException ? e.message : 'QuantumAI failed to respond.');
        messages[idx].streaming = false;
        messages[idx].failed = true;
        messages = [...messages];
      }
      threadError = e is ApiException ? e.message : '$e';
      rethrow;
    } finally {
      final idx = messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        messages[idx].streaming = false;
      }
      aiBusy = false;
      notifyListeners();
    }
  }

  /// Send a WhatsApp-style story reaction as a sealed DM (website parity).
  Future<void> sendStoryReaction(StoryItem story, String emoji) async {
    final ownerId = story.userId;
    final reaction = emoji.trim();
    if (ownerId.isEmpty || reaction.isEmpty) {
      throw ApiException('Invalid story reaction');
    }
    if (ownerId == me.id) {
      throw ApiException("You can't react to your own story");
    }

    QcUser? peer;
    for (final u in users) {
      if (u.id == ownerId) {
        peer = u;
        break;
      }
    }
    if (peer == null) {
      for (final u in friends) {
        if (u.id == ownerId) {
          peer = u;
          break;
        }
      }
    }
    if (peer == null || peer.publicKeys.isEmpty) {
      peer = await auth.api.getUser(ownerId);
    }
    if (peer.publicKeys.isEmpty) {
      throw ApiException("Can't react — missing this user's encryption keys");
    }

    final mySet = await storage.getCurrentKeySet(me.id);
    if (mySet.isEmpty) {
      throw ApiException('Import your encryption keys before reacting');
    }

    final payload = jsonEncode({
      'type': 'story_reaction',
      'storyId': story.id,
      'mediaType': story.mediaType,
      'emoji': reaction,
    });

    final forRecipient = sealMessage(payload, pickRandom(peer.publicKeys));
    final forSender = sealMessage(payload, pickRandom(mySet.map((k) => k.publicKey).toList()));
    final raw = await auth.api.sendMessage({
      'to': ownerId,
      'forRecipient': forRecipient.toJson(),
      'forSender': forSender.toJson(),
      'replyToStory': story.id,
    });

    final msg = await decorate(raw);
    msg.text = payload;

    final convKey = storage.conversationKeyForUser(ownerId);
    await storage.setConversationActivity(
      me.id,
      convKey,
      at: DateTime.now().toUtc().toIso8601String(),
      from: me.id,
    );

    if (selected?.type == ConversationType.dm && selected?.id == ownerId) {
      messages = [...messages, msg];
    }
    _rebuildConversations();
    notifyListeners();
  }

  Future<void> sendText(String draft) async {
    final conv = selected;
    final text = draft.trim();
    if (conv == null || text.isEmpty || sending) return;

    if (selectedIsQuantumAi) {
      if (aiBusy) {
        threadError = 'QuantumAI is already responding';
        notifyListeners();
        return;
      }
      sending = true;
      notifyListeners();
      try {
        clearComposerContext();
        await sendPrivateQuantumAIMessage(text);
      } on ApiException catch (e) {
        threadError = e.message;
      } catch (e) {
        threadError = '$e';
      } finally {
        sending = false;
        notifyListeners();
      }
      return;
    }

    // Lock immediately so a second Enter/tap cannot start another send.
    sending = true;
    notifyListeners();

    if (editing != null) {
      try {
        await editMessageText(editing!, text);
      } finally {
        sending = false;
        notifyListeners();
      }
      return;
    }

    final replyId = replyTo?.id;
    try {
      if (conv.type == ConversationType.group) {
        final group = conv.group ?? groups.firstWhere((g) => g.id == conv.id);
        Map<String, dynamic> payload;
        if (group.isPublic) {
          payload = {'content': text};
        } else {
          payload = {'envelopes': await _sealGroupEnvelopes(text, group)};
        }
        if (replyId != null) payload['replyTo'] = replyId;
        if (disappearSeconds > 0) payload['expiresInSeconds'] = disappearSeconds;
        // Parse @mentions and resolve to user IDs
        final mentionRegex = RegExp(r'@(\w+)');
        final mentionedIds = <String>{};
        for (final match in mentionRegex.allMatches(text)) {
          final username = match.group(1)!.toLowerCase();
          for (final member in group.members) {
            if (member.username.toLowerCase() == username) {
              mentionedIds.add(member.id);
              break;
            }
          }
        }
        if (mentionedIds.isNotEmpty) {
          payload['mentionedUserIds'] = mentionedIds.toList();
        }
        final raw = await auth.api.sendGroupMessage(conv.id, payload);
        final msg = await decorate(raw);
        msg.text = text;
        messages = [...messages, msg];
      } else {
        final peer = conv.peer ?? users.cast<QcUser?>().firstWhere((u) => u?.id == conv.id, orElse: () => me) ?? me;
        final mySet = await storage.getCurrentKeySet(me.id);
        if (mySet.isEmpty || peer.publicKeys.isEmpty) {
          throw ApiException('Missing encryption keys for this conversation');
        }
        final forRecipient = sealMessage(text, pickRandom(peer.publicKeys));
        final forSender = sealMessage(text, pickRandom(mySet.map((k) => k.publicKey).toList()));
        final payload = <String, dynamic>{
          'to': conv.id,
          'forRecipient': forRecipient.toJson(),
          'forSender': forSender.toJson(),
        };
        if (replyId != null) payload['replyTo'] = replyId;
        if (disappearSeconds > 0) payload['expiresInSeconds'] = disappearSeconds;
        final raw = await auth.api.sendMessage(payload);
        final msg = await decorate(raw);
        msg.text = text;
        messages = [...messages, msg];
      }
      clearComposerContext();
      await storage.setConversationActivity(
        me.id,
        conv.key,
        at: DateTime.now().toUtc().toIso8601String(),
        from: me.id,
      );
      _rebuildConversations();
    } on ApiException catch (e) {
      threadError = e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> _sendGroupStructuredPayload(String plaintext, {required String kind}) async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.group || sending) return;
    sending = true;
    notifyListeners();
    try {
      final group = conv.group ?? groups.firstWhere((g) => g.id == conv.id);
      final payload = <String, dynamic>{'kind': kind};
      if (group.isPublic) {
        payload['content'] = plaintext;
      } else {
        payload['envelopes'] = await _sealGroupEnvelopes(plaintext, group);
      }
      if (replyTo != null) payload['replyTo'] = replyTo!.id;
      if (disappearSeconds > 0) payload['expiresInSeconds'] = disappearSeconds;
      final raw = await auth.api.sendGroupMessage(conv.id, payload);
      final msg = await decorate(raw);
      messages = [...messages, msg];
      clearComposerContext();
      await storage.setConversationActivity(
        me.id,
        conv.key,
        at: DateTime.now().toUtc().toIso8601String(),
        from: me.id,
      );
      _rebuildConversations();
    } on ApiException catch (e) {
      threadError = e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> sendPoll(String question, List<String> options) async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.group) return;
    final cleaned = options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    if (question.trim().isEmpty || cleaned.length < 2) {
      threadError = 'Poll needs a question and at least 2 options';
      notifyListeners();
      return;
    }
    await _sendGroupStructuredPayload(
      encodePoll(question: question, options: cleaned),
      kind: 'poll',
    );
  }

  Future<void> sendEvent({
    required String title,
    String? when,
    String location = '',
    String notes = '',
  }) async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.group) return;
    if (title.trim().isEmpty) {
      threadError = 'Event needs a title';
      notifyListeners();
      return;
    }
    await _sendGroupStructuredPayload(
      encodeEvent(title: title, when: when, location: location, notes: notes),
      kind: 'event',
    );
  }

  Future<void> sendAnnouncement(String body) async {
    final conv = selected;
    if (conv == null || conv.type != ConversationType.group) return;
    if (body.trim().isEmpty) {
      threadError = 'Announcement cannot be empty';
      notifyListeners();
      return;
    }
    await _sendGroupStructuredPayload(
      encodeAnnouncement(body),
      kind: 'announcement',
    );
  }

  Future<void> voteOnPoll(ChatMessage message, int optionIndex) async {
    if (!message.isPoll || optionIndex < 0) return;
    try {
      final raw = await auth.api.votePoll(message.id, optionIndex);
      final updated = await decorate(raw);
      messages = messages.map((m) => m.id == message.id ? updated : m).toList();
      notifyListeners();
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
    }
  }

  Future<void> editMessageText(ChatMessage message, String text) async {
    final conv = selected;
    if (conv == null || text.trim().isEmpty) return;
    sending = true;
    notifyListeners();
    try {
      Map<String, dynamic> payload;
      if (conv.type == ConversationType.group) {
        final group = conv.group ?? groups.firstWhere((g) => g.id == conv.id);
        if (group.isPublic) {
          payload = {'content': text.trim()};
        } else {
          payload = {'envelopes': await _sealGroupEnvelopes(text.trim(), group)};
        }
      } else {
        final peer = conv.peer ?? me;
        final mySet = await storage.getCurrentKeySet(me.id);
        payload = {
          'forRecipient': sealMessage(text.trim(), pickRandom(peer.publicKeys)).toJson(),
          'forSender': sealMessage(text.trim(), pickRandom(mySet.map((k) => k.publicKey).toList())).toJson(),
        };
      }
      final raw = await auth.api.editMessage(message.id, payload);
      final updated = await decorate(raw);
      updated.text = text.trim();
      messages = messages.map((m) => m.id == updated.id ? updated : m).toList();
      clearComposerContext();
    } on ApiException catch (e) {
      threadError = e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> deleteMessage(ChatMessage message, {bool forEveryone = false}) async {
    try {
      await auth.api.deleteMessage(message.id, forEveryone: forEveryone);
      if (forEveryone) {
        messages = messages.map((m) {
          if (m.id != message.id) return m;
          m.text = 'Message deleted';
          m.attachment = null;
          return m;
        }).toList();
      } else {
        messages = messages.where((m) => m.id != message.id).toList();
      }
      notifyListeners();
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
    }
  }

  Future<void> sendAttachmentBytes({
    required Uint8List bytes,
    required String filename,
    required String mimetype,
    bool viewOnce = false,
  }) async {
    final conv = selected;
    if (conv == null || sending) return;
    sending = true;
    notifyListeners();
    try {
      if (conv.type == ConversationType.group) {
        final group = conv.group ?? groups.firstWhere((g) => g.id == conv.id);
        final sealed = secretboxSeal(bytes);
        final uploaded = await auth.api.uploadGroupAttachment(
          groupId: conv.id,
          filename: filename,
          mimetype: mimetype,
          sealed: sealed,
        );
        final plaintext = jsonEncode({
          '__qc': 1,
          'type': 'file',
          'attachmentId': '${uploaded['id']}',
          'key': sealed.key,
          'nonce': sealed.nonce,
          'filename': uploaded['filename'] ?? filename,
          'mimetype': uploaded['mimetype'] ?? mimetype,
          'size': uploaded['size'] ?? bytes.length,
        });
        final payload = <String, dynamic>{
          'kind': 'file',
          'attachmentId': '${uploaded['id']}',
        };
        if (group.isPublic) {
          payload['content'] = plaintext;
        } else {
          payload['envelopes'] = await _sealGroupEnvelopes(plaintext, group);
        }
        if (replyTo != null) payload['replyTo'] = replyTo!.id;
        if (viewOnce) payload['viewOnce'] = true;
        final raw = await auth.api.sendGroupMessage(conv.id, payload);
        final msg = await decorate(raw);
        messages = [...messages, msg];
      } else {
        final peer = conv.peer ?? me;
        final mySet = await storage.getCurrentKeySet(me.id);
        if (mySet.isEmpty || peer.publicKeys.isEmpty) {
          throw ApiException('Missing encryption keys for this conversation');
        }
        final forRecipient = sealFileBytes(bytes, pickRandom(peer.publicKeys));
        final forSender = sealFileBytes(bytes, pickRandom(mySet.map((k) => k.publicKey).toList()));
        final uploaded = await auth.api.uploadDmAttachment(
          recipientId: conv.id,
          filename: filename,
          mimetype: mimetype,
          forRecipient: forRecipient,
          forSender: forSender,
        );
        final emptyRecipient = sealMessage('', pickRandom(peer.publicKeys));
        final emptySender = sealMessage('', pickRandom(mySet.map((k) => k.publicKey).toList()));
        final payload = <String, dynamic>{
          'to': conv.id,
          'forRecipient': emptyRecipient.toJson(),
          'forSender': emptySender.toJson(),
          'attachmentId': '${uploaded['id']}',
        };
        if (replyTo != null) payload['replyTo'] = replyTo!.id;
        if (viewOnce) payload['viewOnce'] = true;
        final raw = await auth.api.sendMessage(payload);
        final msg = await decorate(raw);
        messages = [...messages, msg];
      }
      clearComposerContext();
      await storage.setConversationActivity(
        me.id,
        conv.key,
        at: DateTime.now().toUtc().toIso8601String(),
        from: me.id,
      );
      _rebuildConversations();
    } on ApiException catch (e) {
      threadError = e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> sendGifFromUrl(String url) async {
    // Implemented in UI via download + sendAttachmentBytes.
  }

  Future<Uint8List?> decryptAttachment(ChatMessage message) async {
    final att = message.attachment;
    if (att == null) return null;
    final cipher = await auth.api.downloadAttachmentRaw(att.id);
    if (cipher == null) return null;

    if (att.encryption == 'secretbox' || (att.groupKey != null && att.groupNonce != null)) {
      final key = att.groupKey;
      final nonce = att.groupNonce ?? att.secretboxNonce;
      if (key == null || nonce == null) return null;
      return secretboxOpen(cipher, nonce, key);
    }

    final mySet = await storage.getCurrentKeySet(me.id);
    String? secretKey;
    String? nonce;
    String? ephemeral;

    if (att.forSenderTargetPublicKey != null && message.isMine(me.id)) {
      secretKey = await storage.findSecretKeyForPublicKey(me.id, att.forSenderTargetPublicKey!);
      nonce = att.forSenderNonce;
      ephemeral = att.forSenderEphemeralPublicKey;
    }
    if (secretKey == null && att.targetPublicKey != null) {
      secretKey = await storage.findSecretKeyForPublicKey(me.id, att.targetPublicKey!);
      nonce = att.nonce;
      ephemeral = att.ephemeralPublicKey;
    }
    if (secretKey == null || nonce == null || ephemeral == null) {
      // Try each local key against sender envelope then recipient envelope
      for (final k in mySet) {
        if (att.forSenderTargetPublicKey == k.publicKey) {
          secretKey = k.secretKey;
          nonce = att.forSenderNonce;
          ephemeral = att.forSenderEphemeralPublicKey;
          break;
        }
        if (att.targetPublicKey == k.publicKey) {
          secretKey = k.secretKey;
          nonce = att.nonce;
          ephemeral = att.ephemeralPublicKey;
          break;
        }
      }
    }
    if (secretKey == null || nonce == null || ephemeral == null) return null;
    return unsealFileBytes(cipher, nonce: nonce, ephemeralPublicKey: ephemeral, myPrivateKeyHex: secretKey);
  }

  /// Opens a view-once message, fetches the media briefly, then marks it as opened.
  Future<void> openViewOnce(ChatMessage message) async {
    try {
      final raw = await auth.api.openViewOnce(message.id);
      final updated = await decorate(raw);
      messages = messages.map((m) => m.id == updated.id ? updated : m).toList();
      notifyListeners();
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
    }
  }

  Future<void> postStory(
    Uint8List bytes, {
    String filename = 'story.jpg',
    String mimetype = 'image/jpeg',
    String mediaType = 'image',
    String status = 'published',
    String? publishAt,
    String? caption,
    int? ttlMs,
    bool allowReplies = true,
  }) async {
    await auth.api.createStory(
      bytes: bytes,
      filename: filename,
      mimetype: mimetype,
      mediaType: mediaType,
      status: status,
      publishAt: publishAt,
      caption: caption,
      ttlMs: ttlMs,
      allowReplies: allowReplies,
    );
    await refreshStories();
  }

  Future<void> refreshGroup(String groupId) async {
    final g = await auth.api.getGroup(groupId);
    groups = groups.map((x) => x.id == g.id ? g : x).toList();
    if (selected?.id == groupId) {
      selected = Conversation(
        key: selected!.key,
        type: ConversationType.group,
        id: g.id,
        title: g.name,
        subtitle: selected!.subtitle,
        group: g,
        unread: selected!.unread,
        sortAt: selected!.sortAt,
      );
    }
    _rebuildConversations();
  }

  /// Public wrapper for sealing group envelopes (used by forward sheet).
  Future<List<Map<String, dynamic>>> sealGroupEnvelopesPublic(String plaintext, QcGroup group) =>
      _sealGroupEnvelopes(plaintext, group);

  Future<List<Map<String, dynamic>>> _sealGroupEnvelopes(String plaintext, QcGroup group) async {
    final envelopes = <Map<String, dynamic>>[];
    final mySet = await storage.getCurrentKeySet(me.id);
    for (final member in group.members) {
      String? publicKey;
      if (member.id == me.id) {
        if (mySet.isEmpty) throw ApiException('Missing your encryption keys');
        publicKey = pickRandom(mySet.map((k) => k.publicKey).toList());
      } else {
        if (member.publicKeys.isEmpty) {
          throw ApiException('Missing encryption keys for ${member.username}');
        }
        publicKey = pickRandom(member.publicKeys);
      }
      final sealed = sealMessage(plaintext, publicKey);
      envelopes.add({'user': member.id, ...sealed.toJson()});
    }
    return envelopes;
  }

  void onComposerChanged(String value) {
    final conv = selected;
    if (conv == null) return;
    if (conv.type == ConversationType.dm) {
      socket.typingStart(to: conv.id);
    } else {
      socket.typingStart(groupId: conv.id);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (conv.type == ConversationType.dm) {
        socket.typingStop(to: conv.id);
      } else {
        socket.typingStop(groupId: conv.id);
      }
    });
  }

  Future<bool> react(ChatMessage message, String emoji) async {
    final conv = selected;
    if (conv == null) return false;
    try {
      final mySet = await storage.getCurrentKeySet(me.id);
      if (mySet.isEmpty) {
        threadError = 'Missing encryption keys for reactions';
        notifyListeners();
        return false;
      }

      List<String> recipientKeys = [];
      if (conv.type == ConversationType.group) {
        final group = conv.group ?? groups.cast<QcGroup?>().firstWhere((g) => g?.id == conv.id, orElse: () => null);
        if (group == null) return false;
        // Seal reaction for the message author so they can read it.
        final authorId = message.from;
        QcUser? author;
        for (final m in group.members) {
          if (m.id == authorId) {
            author = m;
            break;
          }
        }
        author ??= users.cast<QcUser?>().firstWhere((u) => u?.id == authorId, orElse: () => null);
        recipientKeys = author?.publicKeys ?? [];
        if (recipientKeys.isEmpty && authorId == me.id) {
          recipientKeys = mySet.map((k) => k.publicKey).toList();
        }
      } else {
        final peer = conv.peer ?? users.cast<QcUser?>().firstWhere((u) => u?.id == conv.id, orElse: () => me) ?? me;
        recipientKeys = peer.publicKeys;
        if (recipientKeys.isEmpty && conv.isSelfChat) {
          recipientKeys = mySet.map((k) => k.publicKey).toList();
        }
      }

      if (recipientKeys.isEmpty) {
        threadError = 'Missing encryption keys for reactions';
        notifyListeners();
        return false;
      }

      final raw = await auth.api.reactToMessage(message.id, {
        'forRecipient': sealMessage(emoji, pickRandom(recipientKeys)).toJson(),
        'forSender': sealMessage(emoji, pickRandom(mySet.map((k) => k.publicKey).toList())).toJson(),
      });
      final updated = await decorate(raw);
      messages = messages.map((m) => m.id == updated.id ? updated : m).toList();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      threadError = 'Could not add reaction';
      notifyListeners();
      return false;
    }
  }

  Future<QcGroup?> createGroup(
    String name,
    List<String> memberIds, {
    String visibility = 'private',
    String? joinPolicy,
  }) async {
    try {
      final group = await auth.api.createGroup(
        name: name,
        memberIds: memberIds,
        visibility: visibility,
        joinPolicy: joinPolicy,
      );
      groups = [group, ...groups];
      _rebuildConversations();
      return group;
    } on ApiException catch (e) {
      threadError = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<void> _noteActivity(Map<String, dynamic> raw) async {
    final group = _normalizeUserId(raw['group']);
    final from = _normalizeUserId(raw['from']);
    final to = _normalizeUserId(raw['to']);
    final at = raw['createdAt'] as String? ?? DateTime.now().toUtc().toIso8601String();
    String key;
    if (group != null && group.isNotEmpty) {
      key = storage.conversationKeyForGroup(group);
    } else {
      final other = from == me.id ? to : from;
      if (other == null) return;
      key = storage.conversationKeyForUser(other);
    }
    await storage.setConversationActivity(me.id, key, at: at, from: from);
  }

  bool _rawBelongsToConversation(Map<String, dynamic> raw, Conversation conv) {
    final group = _normalizeUserId(raw['group']);
    if (conv.type == ConversationType.group) {
      return group == conv.id;
    }
    if (conv.isSelfChat) {
      final from = _normalizeUserId(raw['from']);
      final to = _normalizeUserId(raw['to']);
      return group == null && from == me.id && (to == null || to == me.id);
    }
    final from = _normalizeUserId(raw['from']);
    final to = _normalizeUserId(raw['to']);
    final otherId = from == me.id ? to : from;
    return otherId != null && otherId == conv.id;
  }

  String _messageId(Map<String, dynamic> raw) {
    final id = raw['id'] ?? raw['_id'];
    if (id is Map) {
      return '${id['_id'] ?? id['id'] ?? id['\$oid'] ?? id}';
    }
    return '$id';
  }

  Map<String, dynamic> _coerceMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) => MapEntry('$key', _coerceValue(value)));
  }

  dynamic _coerceValue(dynamic value) {
    if (value is Map) return _coerceMap(value);
    if (value is List) return value.map(_coerceValue).toList();
    return value;
  }

  String? _normalizeUserId(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final id = value['_id'] ?? value['id'] ?? value['\$oid'];
      return id == null ? null : '$id';
    }
    final text = '$value';
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  Future<bool> _ingestRawMessage(dynamic raw) async {
    if (raw is! Map) return false;
    final map = _coerceMap(raw);
    final from = _normalizeUserId(map['from']);
    if (from != null && from != me.id && map['group'] == null) {
      if (storage.getHiddenChatIds(me.id).contains(from)) {
        await storage.unhideChat(me.id, from);
      }
    }
    await _noteActivity(map);
    final conv = selected;
    final belongsToOpenThread = conv != null && _rawBelongsToConversation(map, conv);
    if (belongsToOpenThread) {
      final id = _messageId(map);
      if (!messages.any((m) => m.id == id)) {
        final msg = await decorate(map);
        messages = [...messages, msg];
        messages.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        if (!msg.isMine(me.id)) {
          socket.markDelivered(msg.id);
          if (conv.type == ConversationType.dm) {
            unawaited(auth.api.markRead(conv.id));
          }
        }
        notifyListeners();
      }
    }
    _rebuildConversations();
    return belongsToOpenThread;
  }

  /// Polls the server for new messages in the currently open chat.
  Future<void> refreshOpenThread() async {
    final conv = selected;
    if (conv == null || loadingThread || _threadRefreshInFlight) return;
    _threadRefreshInFlight = true;
    try {
      List<Map<String, dynamic>> rows;
      if (_lastThreadSyncAt != null) {
        rows = await auth.api.syncMessages(since: _lastThreadSyncAt);
      } else if (messages.isEmpty) {
        rows = conv.type == ConversationType.dm
            ? await auth.api.getConversation(conv.id)
            : await auth.api.getGroupMessages(conv.id);
      } else {
        final anchor = messages.last.createdAt ?? DateTime.now();
        final since = anchor.subtract(const Duration(seconds: 5)).toUtc().toIso8601String();
        rows = await auth.api.syncMessages(since: since);
      }

      if (selected?.key != conv.key) return;
      for (final row in rows) {
        final map = _coerceMap(row);
        if (!_rawBelongsToConversation(map, conv)) continue;
        await _ingestRawMessage(map);
      }
      _lastThreadSyncAt = DateTime.now().toUtc().toIso8601String();
    } catch (e, st) {
      debugPrint('refreshOpenThread failed: $e\n$st');
    } finally {
      _threadRefreshInFlight = false;
    }
  }

  Future<void> _pollSync() async {
    if (_pollSyncInFlight) return;
    _pollSyncInFlight = true;
    try {
      final rows = await auth.api.syncMessages();
      for (final row in rows) {
        await _noteActivity(row);
      }
      _rebuildConversations();
      await _refreshFriendRequests();
      if (selected != null) {
        await refreshOpenThread();
      }
    } catch (_) {
    } finally {
      _pollSyncInFlight = false;
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  String displayName(String userId) {
    if (userId == me.id) return 'You';
    for (final u in users) {
      if (u.id == userId) return getDisplayName(u);
    }
    for (final g in groups) {
      for (final m in g.members) {
        if (m.id == userId) return getDisplayName(m);
      }
    }
    return 'Member';
  }
}
