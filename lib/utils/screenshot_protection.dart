import 'package:flutter/services.dart';

import '../models/models.dart';

const _channel = MethodChannel('quantumchat/screenshot');

bool userRequiresScreenshotProtection(QcUser? user) =>
    user?.privacy.screenshotProtection == true;

bool groupHasProtectedMember(QcGroup? group, String viewerId) {
  if (group == null) return false;
  for (final member in group.members) {
    if (member.id == viewerId) continue;
    if (userRequiresScreenshotProtection(member)) return true;
  }
  return false;
}

Future<void> setSecureFlag(bool enabled) async {
  try {
    await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
  } catch (_) {
    // Best-effort — iOS / unsupported platforms ignore.
  }
}
