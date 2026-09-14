class PrivacySettings {
  const PrivacySettings({
    this.lastSeen = 'everyone',
    this.online = 'everyone',
    this.readReceipts = 'everyone',
    this.whoCanMessage = 'everyone',
    this.discoverable = 'everyone',
    this.story = 'everyone',
    this.birthdayVisibility = 'everyone',
    this.screenshotProtection = false,
  });

  final String lastSeen;
  final String online;
  final String readReceipts;
  final String whoCanMessage;
  final String discoverable;
  final String story;
  final String birthdayVisibility;
  final bool screenshotProtection;

  factory PrivacySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PrivacySettings();
    var receipts = json['readReceipts'];
    if (receipts is bool) receipts = receipts ? 'everyone' : 'nobody';
    return PrivacySettings(
      lastSeen: json['lastSeen'] as String? ?? 'everyone',
      online: json['online'] as String? ?? 'everyone',
      readReceipts: receipts as String? ?? 'everyone',
      whoCanMessage: json['whoCanMessage'] as String? ?? 'everyone',
      discoverable: json['discoverable'] as String? ?? 'everyone',
      story: json['story'] as String? ?? 'everyone',
      birthdayVisibility: json['birthdayVisibility'] as String? ?? 'everyone',
      screenshotProtection: json['screenshotProtection'] == true,
    );
  }
}

class QcUser {
  const QcUser({
    required this.id,
    required this.username,
    this.displayName = '',
    this.bio = '',
    this.email,
    this.phone = '',
    this.publicKeys = const [],
    this.lastLoginAt,
    this.hasAvatar = false,
    this.emailVerified = false,
    this.privacy = const PrivacySettings(),
    this.isSystemUser = false,
    this.systemRole,
    this.verified = false,
    this.blockedUsers = const [],
    this.friends = const [],
    this.totpEnabled = false,
    this.statusText = '',
    this.dateOfBirth,
    this.timezone = 'UTC',
    this.transliteratedNames = const {},
    this.birthday,
    this.birthdayLocked = false,
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String? email;
  final String phone;
  final List<String> publicKeys;
  final DateTime? lastLoginAt;
  final bool hasAvatar;
  final bool emailVerified;
  final PrivacySettings privacy;
  final bool isSystemUser;
  final String? systemRole;
  final bool verified;
  final List<String> blockedUsers;
  final List<String> friends;
  final bool totpEnabled;
  final String statusText;
  /// Own profile only (toSelfJSON).
  final DateTime? dateOfBirth;
  final String timezone;
  final Map<String, String> transliteratedNames;
  /// Visible birthday for other profiles when privacy allows.
  final DateTime? birthday;
  final bool birthdayLocked;

  String get title => displayName.isNotEmpty ? displayName : username;

  bool get isQuantumAi => systemRole == 'quantum_ai';

  factory QcUser.fromJson(Map<String, dynamic> json) {
    DateTime? lastLogin;
    final rawLogin = json['lastLoginAt'];
    if (rawLogin is String && rawLogin.isNotEmpty) {
      lastLogin = DateTime.tryParse(rawLogin);
    }
    DateTime? dob;
    final rawDob = json['dateOfBirth'] ?? json['birthday'];
    if (rawDob is String && rawDob.isNotEmpty) {
      dob = DateTime.tryParse(rawDob);
    }
    DateTime? birthday;
    final rawBirthday = json['birthday'];
    if (rawBirthday is String && rawBirthday.isNotEmpty) {
      birthday = DateTime.tryParse(rawBirthday);
    }
    final translitRaw = json['transliteratedNames'];
    final translit = <String, String>{};
    if (translitRaw is Map) {
      for (final e in translitRaw.entries) {
        final v = e.value?.toString().trim() ?? '';
        if (v.isNotEmpty) translit['${e.key}'] = v;
      }
    }
    return QcUser(
      id: '${json['id'] ?? json['_id']}',
      username: json['username'] as String? ?? 'user',
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String? ?? '',
      publicKeys: (json['publicKeys'] as List<dynamic>? ?? [])
          .map((k) => k.toString().toLowerCase())
          .toList(),
      lastLoginAt: lastLogin,
      hasAvatar: json['hasAvatar'] == true ||
          (json['avatarPath'] != null &&
              '${json['avatarPath']}'.isNotEmpty &&
              '${json['avatarPath']}' != 'null'),
      emailVerified: json['emailVerified'] == true,
      privacy: PrivacySettings.fromJson(json['privacy'] as Map<String, dynamic>?),
      isSystemUser: json['isSystemUser'] == true,
      systemRole: json['systemRole'] as String?,
      verified: json['verified'] == true,
      blockedUsers: (json['blockedUsers'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      friends: (json['friends'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      totpEnabled: json['totpEnabled'] == true,
      statusText: json['statusText'] as String? ?? '',
      dateOfBirth: dob,
      timezone: json['timezone'] as String? ?? 'UTC',
      transliteratedNames: translit,
      birthday: birthday ?? dob,
      birthdayLocked: json['birthdayLocked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'bio': bio,
        'email': email,
        'phone': phone,
        'publicKeys': publicKeys,
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'hasAvatar': hasAvatar,
        'emailVerified': emailVerified,
        'privacy': {
          'lastSeen': privacy.lastSeen,
          'online': privacy.online,
          'readReceipts': privacy.readReceipts,
          'whoCanMessage': privacy.whoCanMessage,
          'discoverable': privacy.discoverable,
          'story': privacy.story,
          'birthdayVisibility': privacy.birthdayVisibility,
          'screenshotProtection': privacy.screenshotProtection,
        },
        'isSystemUser': isSystemUser,
        'systemRole': systemRole,
        'verified': verified,
        'blockedUsers': blockedUsers,
        'friends': friends,
        'totpEnabled': totpEnabled,
        'statusText': statusText,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'timezone': timezone,
        'transliteratedNames': transliteratedNames,
        'birthday': birthday?.toIso8601String(),
        'birthdayLocked': birthdayLocked,
      };

  QcUser copyWith({
    String? displayName,
    String? bio,
    List<String>? publicKeys,
    bool? hasAvatar,
    bool? emailVerified,
    PrivacySettings? privacy,
    String? statusText,
    DateTime? dateOfBirth,
    String? timezone,
    Map<String, String>? transliteratedNames,
  }) {
    return QcUser(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      email: email,
      phone: phone,
      publicKeys: publicKeys ?? this.publicKeys,
      lastLoginAt: lastLoginAt,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      emailVerified: emailVerified ?? this.emailVerified,
      privacy: privacy ?? this.privacy,
      isSystemUser: isSystemUser,
      systemRole: systemRole,
      verified: verified,
      blockedUsers: blockedUsers,
      friends: friends,
      totpEnabled: totpEnabled,
      statusText: statusText ?? this.statusText,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      timezone: timezone ?? this.timezone,
      transliteratedNames: transliteratedNames ?? this.transliteratedNames,
      birthday: birthday,
      birthdayLocked: birthdayLocked,
    );
  }
}

class QcGroup {
  const QcGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.members = const [],
    this.admins = const [],
    this.hasPhoto = false,
    this.visibility = 'private',
    this.joinPolicy = 'invite',
    this.inviteEnabled = false,
    this.inviteCode,
    this.updatedAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final List<QcUser> members;
  final List<String> admins;
  final bool hasPhoto;
  final String visibility;
  /// private: invite · public: open | request
  final String joinPolicy;
  final bool inviteEnabled;
  final String? inviteCode;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  bool get isPublic => visibility == 'public';

  bool isAdmin(String userId) {
    if (admins.isNotEmpty) return admins.contains(userId);
    return false;
  }

  factory QcGroup.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    final code = json['inviteCode']?.toString();
    final visibility = json['visibility'] as String? ?? 'private';
    var joinPolicy = json['joinPolicy'] as String? ?? 'invite';
    if (visibility == 'public' && joinPolicy != 'request') joinPolicy = 'open';
    return QcGroup(
      id: '${json['id'] ?? json['_id']}',
      name: json['name'] as String? ?? 'Group',
      description: json['description'] as String? ?? '',
      members: (json['members'] as List<dynamic>? ?? []).map((m) {
        if (m is Map<String, dynamic>) return QcUser.fromJson(m);
        return QcUser(id: '$m', username: 'member');
      }).toList(),
      admins: (json['admins'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      hasPhoto: json['hasPhoto'] == true,
      visibility: visibility,
      joinPolicy: joinPolicy,
      inviteEnabled: json['inviteEnabled'] == true,
      inviteCode: (code != null && code.isNotEmpty && code != 'null') ? code : null,
      updatedAt: parse(json['updatedAt']),
      createdAt: parse(json['createdAt']),
    );
  }
}

/// Lightweight public group from GET /groups/discover.
class DiscoverGroup {
  const DiscoverGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.memberCount = 0,
    this.hasPhoto = false,
    this.joinPolicy = 'open',
    this.joinRequestPending = false,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final bool hasPhoto;
  final String joinPolicy;
  final bool joinRequestPending;

  bool get requiresRequest => joinPolicy == 'request';

  factory DiscoverGroup.fromJson(Map<String, dynamic> json) {
    return DiscoverGroup(
      id: '${json['id'] ?? json['_id']}',
      name: json['name'] as String? ?? 'Group',
      description: json['description'] as String? ?? '',
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      hasPhoto: json['hasPhoto'] == true,
      joinPolicy: json['joinPolicy'] == 'request' ? 'request' : 'open',
      joinRequestPending: json['joinRequestPending'] == true,
    );
  }

  DiscoverGroup copyWith({bool? joinRequestPending}) {
    return DiscoverGroup(
      id: id,
      name: name,
      description: description,
      memberCount: memberCount,
      hasPhoto: hasPhoto,
      joinPolicy: joinPolicy,
      joinRequestPending: joinRequestPending ?? this.joinRequestPending,
    );
  }
}

class GroupJoinRequest {
  const GroupJoinRequest({
    required this.id,
    required this.user,
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final QcUser user;
  final String status;
  final DateTime? createdAt;

  factory GroupJoinRequest.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    final QcUser user;
    if (userRaw is Map<String, dynamic>) {
      user = QcUser.fromJson(userRaw);
    } else {
      user = QcUser(id: '$userRaw', username: 'user');
    }
    return GroupJoinRequest(
      id: '${json['id'] ?? json['_id']}',
      user: user,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

class Reaction {
  const Reaction({required this.userId, this.emoji});
  final String userId;
  final String? emoji;
}

class AttachmentMeta {
  const AttachmentMeta({
    required this.id,
    this.filename = 'attachment',
    this.mimetype = 'application/octet-stream',
    this.size = 0,
    this.encryption = 'sealed',
    this.nonce,
    this.ephemeralPublicKey,
    this.targetPublicKey,
    this.forSenderNonce,
    this.forSenderEphemeralPublicKey,
    this.forSenderTargetPublicKey,
    this.secretboxNonce,
    this.groupKey,
    this.groupNonce,
  });

  final String id;
  final String filename;
  final String mimetype;
  final int size;
  final String encryption;
  final String? nonce;
  final String? ephemeralPublicKey;
  final String? targetPublicKey;
  final String? forSenderNonce;
  final String? forSenderEphemeralPublicKey;
  final String? forSenderTargetPublicKey;
  final String? secretboxNonce;
  /// Distributed via sealed group plaintext for secretbox files.
  final String? groupKey;
  final String? groupNonce;

  bool get isImage => mimetype.startsWith('image/');
  bool get isGif => mimetype == 'image/gif' || filename.toLowerCase().endsWith('.gif');
  bool get isVideo => mimetype.startsWith('video/');
  bool get isAudio {
    final name = filename.toLowerCase();
    return mimetype.startsWith('audio/') ||
        name.startsWith('voice-note') ||
        RegExp(r'\.(webm|ogg|mp3|m4a|wav|aac)$').hasMatch(name);
  }

  String get inferredMediaCategory {
    if (isAudio) return 'voice';
    if (isImage) return 'photo';
    if (isVideo) return 'video';
    return 'document';
  }

  factory AttachmentMeta.fromJson(Map<String, dynamic>? json, {String? groupKey, String? groupNonce}) {
    if (json == null) {
      throw const FormatException('Missing attachment');
    }
    return AttachmentMeta(
      id: '${json['id'] ?? json['_id']}',
      filename: json['filename'] as String? ?? 'attachment',
      mimetype: json['mimetype'] as String? ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      encryption: json['encryption'] as String? ?? 'sealed',
      nonce: json['nonce'] as String?,
      ephemeralPublicKey: json['ephemeralPublicKey'] as String?,
      targetPublicKey: json['targetPublicKey'] as String?,
      forSenderNonce: json['forSenderNonce'] as String?,
      forSenderEphemeralPublicKey: json['forSenderEphemeralPublicKey'] as String?,
      forSenderTargetPublicKey: json['forSenderTargetPublicKey'] as String?,
      secretboxNonce: json['secretboxNonce'] as String? ?? groupNonce,
      groupKey: groupKey,
      groupNonce: groupNonce ?? json['secretboxNonce'] as String?,
    );
  }
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.from,
    this.createdAt,
  });

  final String id;
  final QcUser from;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    final fromRaw = json['from'];
    final QcUser from;
    if (fromRaw is Map<String, dynamic>) {
      from = QcUser.fromJson(fromRaw);
    } else {
      from = QcUser(id: '$fromRaw', username: 'user');
    }
    return FriendRequest(
      id: '${json['id'] ?? json['_id']}',
      from: from,
      createdAt: json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

class StoryItem {
  const StoryItem({
    required this.id,
    required this.userId,
    required this.username,
    this.hasAvatar = false,
    this.mediaType = 'image',
    this.mimetype = 'image/jpeg',
    this.sealed = false,
    this.createdAt,
    this.expiresAt,
    this.viewed = false,
    this.status = 'published',
    this.caption = '',
    this.publishAt,
    this.allowReplies = true,
  });

  final String id;
  final String userId;
  final String username;
  final bool hasAvatar;
  final String mediaType;
  final String mimetype;
  final bool sealed;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool viewed;
  final String status;
  final String caption;
  final DateTime? publishAt;
  final bool allowReplies;

  bool get isDraft => status == 'draft';
  bool get isScheduled => status == 'scheduled';

  factory StoryItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String userId = '';
    String username = 'User';
    bool hasAvatar = false;
    if (user is Map) {
      userId = '${user['id'] ?? user['_id'] ?? ''}';
      username = user['username'] as String? ?? 'User';
      hasAvatar = user['hasAvatar'] == true;
    } else if (user != null) {
      userId = '$user';
    }
    return StoryItem(
      id: '${json['id'] ?? json['_id']}',
      userId: userId,
      username: username,
      hasAvatar: hasAvatar,
      mediaType: json['mediaType'] as String? ?? 'image',
      mimetype: json['mimetype'] as String? ?? 'image/jpeg',
      sealed: json['sealed'] == true,
      createdAt: json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null,
      expiresAt: json['expiresAt'] is String ? DateTime.tryParse(json['expiresAt'] as String) : null,
      viewed: json['viewedByMe'] == true || json['viewed'] == true,
      status: json['status'] as String? ?? 'published',
      caption: json['caption'] as String? ?? '',
      publishAt: json['publishAt'] is String ? DateTime.tryParse(json['publishAt'] as String) : null,
      allowReplies: json['allowReplies'] != false,
    );
  }
}

class HighlightItem {
  const HighlightItem({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.hasCover = false,
    this.ownerId,
  });

  final String id;
  final String name;
  final int itemCount;
  final bool hasCover;
  final String? ownerId;

  factory HighlightItem.fromJson(Map<String, dynamic> json) {
    return HighlightItem(
      id: '${json['id'] ?? json['_id']}',
      name: json['name'] as String? ?? 'Highlight',
      itemCount: (json['itemCount'] as num?)?.toInt() ??
          (json['items'] is List ? (json['items'] as List).length : 0),
      hasCover: json['hasCover'] == true ||
          (json['coverStoragePath'] != null && '${json['coverStoragePath']}'.isNotEmpty),
      ownerId: json['owner'] != null
          ? (json['owner'] is Map ? '${json['owner']['id'] ?? json['owner']['_id']}' : '${json['owner']}')
          : null,
    );
  }
}

class ForwardedFromMeta {
  const ForwardedFromMeta({this.messageId, this.username});
  final String? messageId;
  final String? username;

  factory ForwardedFromMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ForwardedFromMeta();
    return ForwardedFromMeta(
      messageId: json['messageId'] as String?,
      username: json['username'] as String?,
    );
  }
}

class EditHistoryEntry {
  const EditHistoryEntry({required this.editedAt, this.text});
  final DateTime editedAt;
  final String? text;
}

class PollVote {
  const PollVote({required this.userId, required this.optionIndex});
  final String userId;
  final int optionIndex;

  factory PollVote.fromJson(Map<String, dynamic> json) {
    return PollVote(
      userId: '${json['user'] ?? json['userId'] ?? ''}',
      optionIndex: (json['optionIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

class PollData {
  const PollData({required this.question, required this.options});
  final String question;
  final List<String> options;

  factory PollData.fromPayload(Map<String, dynamic> payload) {
    return PollData(
      question: payload['question'] as String? ?? 'Poll',
      options: (payload['options'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
    );
  }
}

class EventData {
  const EventData({
    required this.title,
    this.when,
    this.location = '',
    this.notes = '',
  });
  final String title;
  final String? when;
  final String location;
  final String notes;

  factory EventData.fromPayload(Map<String, dynamic> payload) {
    return EventData(
      title: payload['title'] as String? ?? 'Event',
      when: payload['when'] as String?,
      location: payload['where'] as String? ?? payload['location'] as String? ?? '',
      notes: payload['notes'] as String? ?? '',
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.from,
    this.to,
    this.groupId,
    this.text,
    this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    this.expiresAt,
    this.pending = false,
    this.reactions = const [],
    this.replyToId,
    this.replyToText,
    this.kind = 'text',
    this.attachment,
    this.forwardedFrom,
    this.isPinned = false,
    this.isStarred = false,
    this.editHistory = const [],
    this.viewOnce = false,
    this.viewOnceOpenedAt,
    this.viewOnceOpenedBy,
    this.viewOnceMediaKind,
    this.mentionedUserIds = const [],
    this.pollData,
    this.pollVotes = const [],
    this.eventData,
    this.announcementBody,
    this.mediaCategory,
  });

  final String id;
  final String from;
  final String? to;
  final String? groupId;
  String? text;
  final DateTime? createdAt;
  DateTime? deliveredAt;
  DateTime? readAt;
  DateTime? editedAt;
  final DateTime? expiresAt;
  final bool pending;
  List<Reaction> reactions;
  final String? replyToId;
  final String? replyToText;
  final String kind;
  AttachmentMeta? attachment;
  final ForwardedFromMeta? forwardedFrom;
  bool isPinned;
  bool isStarred;
  List<EditHistoryEntry> editHistory;
  bool viewOnce;
  DateTime? viewOnceOpenedAt;
  String? viewOnceOpenedBy;
  String? viewOnceMediaKind;
  final List<String> mentionedUserIds;
  PollData? pollData;
  List<PollVote> pollVotes;
  EventData? eventData;
  String? announcementBody;
  /// Server mediaCategory: photo | video | voice | document
  final String? mediaCategory;

  bool isMine(String myId) => from == myId;
  bool get hasMedia => attachment != null || kind == 'file' || kind == 'image' || kind == 'gif';
  bool get isDisappearing => expiresAt != null;
  bool get isPoll => kind == 'poll' || pollData != null;
  bool get isEvent => kind == 'event' || eventData != null;
  bool get isAnnouncement => kind == 'announcement' || announcementBody != null;

  String? get effectiveMediaCategory {
    if (mediaCategory != null && mediaCategory!.isNotEmpty) return mediaCategory;
    return attachment?.inferredMediaCategory;
  }

  bool matchesClearScope(String scope) {
    if (scope == 'all') return true;
    if (scope == 'starred') return isStarred;
    final category = effectiveMediaCategory;
    final hasAttachment = attachment != null;
    if (scope == 'text') return category == null && !hasAttachment;
    return category == scope;
  }
}

enum ConversationType { dm, group }

class Conversation {
  Conversation({
    required this.key,
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.peer,
    this.group,
    this.unread = false,
    this.sortAt = '',
    this.online = false,
    this.isSelfChat = false,
    this.muted = false,
    this.archived = false,
  });

  final String key;
  final ConversationType type;
  final String id;
  final String title;
  final String? subtitle;
  final QcUser? peer;
  final QcGroup? group;
  bool unread;
  String sortAt;
  bool online;
  final bool isSelfChat;
  bool muted;
  bool archived;
}

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}
