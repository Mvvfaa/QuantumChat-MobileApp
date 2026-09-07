import '../crypto/key_storage.dart';
import '../models/models.dart';

const nonLatinScriptLangs = {'ur', 'ar', 'fa', 'hi', 'zh', 'ru'};

/// Localized display name — uses transliteration for non-Latin UI languages.
String getDisplayName(QcUser? user, {String? lang}) {
  if (user == null) return '';
  final langCode = (lang ?? KeyStorage.instance.getLanguage() ?? 'en')
      .trim()
      .toLowerCase()
      .split('-')
      .first;

  if (nonLatinScriptLangs.contains(langCode)) {
    final t = user.transliteratedNames[langCode];
    if (t != null && t.trim().isNotEmpty) return t.trim();
  }

  if (user.displayName.trim().isNotEmpty) return user.displayName.trim();
  if (user.username.trim().isNotEmpty) return user.username.trim();
  return '';
}
