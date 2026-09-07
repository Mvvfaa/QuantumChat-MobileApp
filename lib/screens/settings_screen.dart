import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../crypto/key_storage.dart';
import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_app_icons.dart';
import '../theme/qc_theme.dart';
import '../utils/timezones.dart';
import '../widgets/avatar_cache.dart';
import '../widgets/common.dart';
import 'notification_settings_screen.dart';
import 'sessions_screen.dart';
import 'starred_messages_screen.dart';
import 'wallpaper_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final displayName = TextEditingController(text: context.read<AuthController>().user?.displayName ?? '');
  late final bio = TextEditingController(text: context.read<AuthController>().user?.bio ?? '');
  late final statusText = TextEditingController(text: context.read<AuthController>().user?.statusText ?? '');
  late final apiBase = TextEditingController(text: context.read<AuthController>().apiBase);
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final totpCode = TextEditingController();
  final disablePassword = TextEditingController();
  late final translitUr = TextEditingController();
  late final translitAr = TextEditingController();
  late final translitHi = TextEditingController();
  late final translitRu = TextEditingController();
  late final translitZh = TextEditingController();
  late final translitFa = TextEditingController();
  DateTime? dateOfBirth;
  String timezone = 'UTC';
  String? status;
  String? setupSecret;
  String? setupOtpauth;
  List<QcUser> blocked = [];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    dateOfBirth = user?.dateOfBirth;
    timezone = user?.timezone ?? pickDefaultTimezone();
    translitUr.text = user?.transliteratedNames['ur'] ?? '';
    translitAr.text = user?.transliteratedNames['ar'] ?? '';
    translitHi.text = user?.transliteratedNames['hi'] ?? '';
    translitRu.text = user?.transliteratedNames['ru'] ?? '';
    translitZh.text = user?.transliteratedNames['zh'] ?? '';
    translitFa.text = user?.transliteratedNames['fa'] ?? '';
    _loadBlocked();
  }

  @override
  void dispose() {
    displayName.dispose();
    bio.dispose();
    statusText.dispose();
    apiBase.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    totpCode.dispose();
    disablePassword.dispose();
    translitUr.dispose();
    translitAr.dispose();
    translitHi.dispose();
    translitRu.dispose();
    translitZh.dispose();
    translitFa.dispose();
    super.dispose();
  }

  Future<void> _showLanguagePicker() async {
    const languages = <(String, String)>[
      ('en', 'English'),
      ('ur', 'اردو (Urdu)'),
      ('ar', 'العربية (Arabic)'),
      ('tr', 'Türkçe (Turkish)'),
      ('es', 'Español (Spanish)'),
      ('fr', 'Français (French)'),
      ('de', 'Deutsch (German)'),
      ('hi', 'हिन्दी (Hindi)'),
      ('zh', '中文 (Chinese)'),
      ('ru', 'Русский (Russian)'),
      ('fa', 'فارسی (Persian)'),
    ];
    final colors = context.read<ThemeController>().colors;
    final current = KeyStorage.instance.getLanguage() ?? 'en';
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('Select language', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800))),
            ...languages.map(
              (l) => ListTile(
                title: Text(l.$2, style: TextStyle(color: colors.textPrimary)),
                trailing: current == l.$1 ? Icon(Icons.check, color: colors.accent) : null,
                onTap: () => Navigator.pop(ctx, l.$1),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final api = context.read<AuthController>().api;
    try {
      await KeyStorage.instance.setLanguage(picked);
      await api.updateLanguage(picked);
      if (mounted) {
        setState(() => status = 'Language updated');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => status = e.message);
    }
  }

  Future<void> _loadBlocked() async {
    try {
      final list = await context.read<AuthController>().api.listBlocked();
      if (mounted) setState(() => blocked = list);
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthController>();
    try {
      final updated = await auth.api.updateProfile({
        'displayName': displayName.text.trim(),
        'bio': bio.text.trim(),
        'statusText': statusText.text.trim(),
        'dateOfBirth': dateOfBirth == null
            ? ''
            : '${dateOfBirth!.year.toString().padLeft(4, '0')}-'
                '${dateOfBirth!.month.toString().padLeft(2, '0')}-'
                '${dateOfBirth!.day.toString().padLeft(2, '0')}',
        'timezone': timezone,
        'transliteratedNames': {
          'ur': translitUr.text.trim(),
          'ar': translitAr.text.trim(),
          'fa': translitFa.text.trim(),
          'hi': translitHi.text.trim(),
          'zh': translitZh.text.trim(),
          'ru': translitRu.text.trim(),
        },
      });
      auth.updateUser(updated);
      setState(() => status = 'Profile saved');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => dateOfBirth = picked);
  }

  Future<void> _savePrivacy(String field, dynamic value) async {
    final auth = context.read<AuthController>();
    try {
      final updated = await auth.api.updatePrivacy({field: value});
      auth.updateUser(updated);
      setState(() {});
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _changeAvatar() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    try {
      final updated = await context.read<AuthController>().api.uploadAvatar(
            bytes,
            filename: file.name,
            mime: file.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      AvatarCache.instance.bust(updated.id);
      context.read<AuthController>().updateUser(updated);
      setState(() => status = 'Avatar updated');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _removeAvatar() async {
    final auth = context.read<AuthController>();
    final user = auth.user;
    if (user == null || !user.hasAvatar) return;
    try {
      await auth.api.deleteAvatar();
      if (!mounted) return;
      AvatarCache.instance.bust(user.id);
      auth.updateUser(user.copyWith(hasAvatar: false));
      setState(() => status = 'Photo removed');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _changePassword() async {
    try {
      await context.read<AuthController>().api.changePassword(
            currentPassword: currentPassword.text,
            newPassword: newPassword.text,
          );
      currentPassword.clear();
      newPassword.clear();
      setState(() => status = 'Password changed');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _setup2fa() async {
    try {
      final data = await context.read<AuthController>().api.setup2fa();
      setState(() {
        setupSecret = data['secret'] as String?;
        setupOtpauth = data['otpauthUrl'] as String?;
        status = 'Add the secret in your authenticator app, then enter a code.';
      });
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _enable2fa() async {
    try {
      final user = await context.read<AuthController>().api.enable2fa(totpCode.text.trim());
      if (!mounted) return;
      context.read<AuthController>().updateUser(user);
      totpCode.clear();
      setupSecret = null;
      setState(() => status = '2FA enabled');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  Future<void> _disable2fa() async {
    try {
      final user = await context.read<AuthController>().api.disable2fa(
            password: disablePassword.text,
            token: totpCode.text.trim(),
          );
      if (!mounted) return;
      context.read<AuthController>().updateUser(user);
      disablePassword.clear();
      totpCode.clear();
      setState(() => status = '2FA disabled');
    } on ApiException catch (e) {
      setState(() => status = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;
    final user = auth.user!;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Stack(
              children: [
                UserAvatar(name: user.title, userId: user.id, hasAvatar: user.hasAvatar, size: 72),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: colors.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _changeAvatar,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text('@${user.username}', style: TextStyle(color: colors.textMuted))),
          if (user.hasAvatar) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _removeAvatar,
                child: Text('Remove photo', style: TextStyle(color: colors.error)),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(status!, textAlign: TextAlign.center, style: TextStyle(color: colors.accentCyan)),
          ],
          const SizedBox(height: 20),
          _Section(title: 'Profile', colors: colors),
          TextField(controller: displayName, decoration: const InputDecoration(hintText: 'Display name')),
          const SizedBox(height: 10),
          TextField(controller: bio, maxLines: 3, decoration: const InputDecoration(hintText: 'Bio')),
          const SizedBox(height: 10),
          TextField(controller: statusText, decoration: const InputDecoration(hintText: 'Status (e.g. Available, Busy…)')),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date of birth', style: TextStyle(color: colors.textPrimary)),
            subtitle: Text(
              dateOfBirth == null
                  ? 'Not set — used for birthday reminders'
                  : '${dateOfBirth!.year}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}',
              style: TextStyle(color: colors.textMuted),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dateOfBirth != null)
                  IconButton(
                    icon: Icon(Icons.clear, color: colors.textMuted),
                    onPressed: () => setState(() => dateOfBirth = null),
                  ),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: colors.accent),
                  onPressed: _pickDob,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Timezone'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: timezoneOptions.contains(timezone) ? timezone : 'UTC',
                items: timezoneOptions
                    .map((tz) => DropdownMenuItem(value: tz, child: Text(tz, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => timezone = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Name in other scripts', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Shown when friends use Urdu, Arabic, Hindi, etc.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(controller: translitUr, decoration: const InputDecoration(hintText: 'Urdu name')),
          const SizedBox(height: 8),
          TextField(controller: translitAr, decoration: const InputDecoration(hintText: 'Arabic name')),
          const SizedBox(height: 8),
          TextField(controller: translitFa, decoration: const InputDecoration(hintText: 'Persian name')),
          const SizedBox(height: 8),
          TextField(controller: translitHi, decoration: const InputDecoration(hintText: 'Hindi name')),
          const SizedBox(height: 8),
          TextField(controller: translitZh, decoration: const InputDecoration(hintText: 'Chinese name')),
          const SizedBox(height: 8),
          TextField(controller: translitRu, decoration: const InputDecoration(hintText: 'Russian name')),
          const SizedBox(height: 10),
          QcPrimaryButton(label: 'Save profile', onPressed: _saveProfile),
          const SizedBox(height: 24),
          _Section(title: 'Appearance', colors: colors),
          Text(
            'Current look: ${theme.id.label}',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _buildAppearanceCard(
            colors: colors,
            title: 'Display mode',
            hint: 'Everyday light, dark, or eyecare',
            child: _ModePill(
              selected: theme.id,
              colors: colors,
              onSelect: theme.setTheme,
            ),
          ),
          const SizedBox(height: 12),
          _buildAppearanceCard(
            colors: colors,
            title: 'Dreamy themes',
            hint: theme.isFunTheme ? '${theme.id.label} is active' : 'Pick a decorative skin',
            badge: 'FX',
            child: _FunThemeGrid(
              selected: theme.id,
              colors: colors,
              onSelect: theme.setTheme,
            ),
          ),
          const SizedBox(height: 12),
          _buildAppearanceCard(
            colors: colors,
            title: 'App icon',
            hint: 'In-app logo color',
            badge: 'Icon',
            softBadge: true,
            child: _AppIconGrid(
              selectedId: theme.appIcon.id,
              colors: colors,
              onSelect: theme.setAppIcon,
            ),
          ),
          const SizedBox(height: 24),
          _Section(title: 'Privacy', colors: colors),
          _PrivacyTile(
            label: 'Last seen',
            value: user.privacy.lastSeen,
            onChanged: (v) => _savePrivacy('lastSeen', v),
            colors: colors,
          ),
          _PrivacyTile(
            label: 'Online status',
            value: user.privacy.online,
            onChanged: (v) => _savePrivacy('online', v),
            colors: colors,
          ),
          _PrivacyTile(
            label: 'Read receipts',
            value: user.privacy.readReceipts,
            onChanged: (v) => _savePrivacy('readReceipts', v),
            colors: colors,
          ),
          _PrivacyTile(
            label: 'Who can message you',
            value: user.privacy.whoCanMessage,
            onChanged: (v) => _savePrivacy('whoCanMessage', v),
            colors: colors,
          ),
          _PrivacyTile(
            label: 'Stories',
            value: user.privacy.story,
            onChanged: (v) => _savePrivacy('story', v),
            colors: colors,
          ),
          _PrivacyTile(
            label: 'Birthday visibility',
            value: user.privacy.birthdayVisibility,
            onChanged: (v) => _savePrivacy('birthdayVisibility', v),
            colors: colors,
            options: const ['everyone', 'friends', 'onlyMe'],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Screenshot protection', style: TextStyle(color: colors.textPrimary)),
            subtitle: Text(
              'When on, other people cannot screenshot chats with you (Android).',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            value: user.privacy.screenshotProtection,
            activeThumbColor: colors.accent,
            onChanged: (v) => _savePrivacy('screenshotProtection', v),
          ),
          const SizedBox(height: 24),
          _Section(title: 'Blocked users', colors: colors),
          if (blocked.isEmpty)
            Text('No blocked users', style: TextStyle(color: colors.textMuted))
          else
            ...blocked.map(
              (u) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar, size: 36),
                title: Text(u.title),
                trailing: TextButton(
                  onPressed: () async {
                    await auth.api.unblockUser(u.id);
                    await _loadBlocked();
                  },
                  child: const Text('Unblock'),
                ),
              ),
            ),
          const SizedBox(height: 24),
          _Section(title: 'Password', colors: colors),
          TextField(
            controller: currentPassword,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Current password'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: newPassword,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'New password'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _changePassword, child: const Text('Change password')),
          const SizedBox(height: 24),
          _Section(title: 'Two-factor authentication', colors: colors),
          Text(
            user.totpEnabled
                ? '2FA is enabled on your account.'
                : 'Add an authenticator app for extra login security.',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (!user.totpEnabled) ...[
            OutlinedButton(onPressed: _setup2fa, child: const Text('Set up 2FA')),
            if (setupSecret != null) ...[
              const SizedBox(height: 8),
              SelectableText('Secret: $setupSecret', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              if (setupOtpauth != null)
                SelectableText(setupOtpauth!, style: TextStyle(color: colors.textMuted, fontSize: 11)),
              const SizedBox(height: 8),
              TextField(
                controller: totpCode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '6-digit code'),
              ),
              const SizedBox(height: 8),
              QcPrimaryButton(label: 'Enable 2FA', onPressed: _enable2fa),
            ],
          ] else ...[
            TextField(
              controller: disablePassword,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: totpCode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Authenticator code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: colors.error),
              onPressed: _disable2fa,
              child: const Text('Disable 2FA'),
            ),
          ],
          const SizedBox(height: 24),
          _Section(title: 'Server', colors: colors),
          Text(
            'Point this app at the QuantumChat backend. Android emulator: http://10.0.2.2:5000',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(controller: apiBase, decoration: const InputDecoration(hintText: 'http://10.0.2.2:5000')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              await auth.setApiBase(apiBase.text.trim());
              setState(() => status = 'API URL saved. Log out and back in if you were already connected.');
            },
            child: const Text('Save API URL'),
          ),
          const SizedBox(height: 24),
          _Section(title: 'Messages', colors: colors),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.star, color: colors.accentCyan),
            title: Text('Starred Messages', style: TextStyle(color: colors.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StarredMessagesScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.notifications_outlined, color: colors.accentCyan),
            title: Text('Notifications', style: TextStyle(color: colors.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.wallpaper_outlined, color: colors.accentCyan),
            title: Text('Chat Wallpaper', style: TextStyle(color: colors.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language, color: colors.accentCyan),
            title: Text('Language', style: TextStyle(color: colors.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: _showLanguagePicker,
          ),
          const SizedBox(height: 24),
          _Section(title: 'Security', colors: colors),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.devices_outlined, color: colors.accentCyan),
            title: Text('Active Sessions', style: TextStyle(color: colors.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionsScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Encryption keys', style: TextStyle(color: colors.textPrimary)),
            subtitle: Text(
              'Private keys stay on this device. Logout does not delete them.',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: colors.error, side: BorderSide(color: colors.error)),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text('Log out?', style: TextStyle(color: colors.textPrimary)),
                  content: Text(
                    'You will need to sign in again. Encryption keys stay on this phone.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                context.read<ChatController>().stop();
                await auth.logout();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.colors});
  final String title;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
    );
  }
}

Widget _buildAppearanceCard({
  required QcColors colors,
  required String title,
  required String hint,
  required Widget child,
  String? badge,
  bool softBadge = false,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
    decoration: BoxDecoration(
      color: colors.elevated.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.border.withValues(alpha: 0.85)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.accent.withValues(alpha: 0.08),
          colors.elevated.withValues(alpha: 0.35),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(hint, style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.3)),
                ],
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: softBadge ? colors.accentMuted : colors.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: softBadge ? colors.accent : colors.bubbleMineFg,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.selected,
    required this.colors,
    required this.onSelect,
  });

  final QcThemeId selected;
  final QcColors colors;
  final ValueChanged<QcThemeId> onSelect;

  static const _modes = <(QcThemeId, IconData, String)>[
    (QcThemeId.light, Icons.wb_sunny_outlined, 'Light Theme'),
    (QcThemeId.dark, Icons.dark_mode_outlined, 'Dark Theme'),
    (QcThemeId.eyecare, Icons.remove_red_eye_outlined, 'Eyecare Theme'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (final entry in _modes)
            Expanded(
              child: _ModeButton(
                active: selected.isModeTheme && selected == entry.$1,
                icon: entry.$2,
                label: entry.$3,
                colors: colors,
                onTap: () => onSelect(entry.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final QcColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: active ? colors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: active ? colors.bubbleMineFg : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FunThemeGrid extends StatelessWidget {
  const _FunThemeGrid({
    required this.selected,
    required this.colors,
    required this.onSelect,
  });

  final QcThemeId selected;
  final QcColors colors;
  final ValueChanged<QcThemeId> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: QcThemeIdX.funThemes.map((id) {
        final on = selected == id;
        return SizedBox(
          width: 92,
          child: InkWell(
            onTap: () => onSelect(id),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? colors.accent : colors.border.withValues(alpha: 0.7),
                      width: on ? 2.4 : 1,
                    ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: id.previewGradient,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  id.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on ? colors.accentCyan : colors.textSecondary,
                    fontSize: 11,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AppIconGrid extends StatelessWidget {
  const _AppIconGrid({
    required this.selectedId,
    required this.colors,
    required this.onSelect,
  });

  final String selectedId;
  final QcColors colors;
  final ValueChanged<QcAppIcon> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: QcAppIcon.all.map((icon) {
        final on = selectedId == icon.id;
        return SizedBox(
          width: 84,
          child: InkWell(
            onTap: () => onSelect(icon),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: on ? colors.accent : colors.border.withValues(alpha: 0.8),
                      width: on ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: icon.swatch.withValues(alpha: on ? 0.45 : 0.18),
                        blurRadius: on ? 16 : 8,
                        spreadRadius: on ? 1 : 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Image.asset(
                          icon.asset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: colors.textMuted),
                        ),
                      ),
                      if (on)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.surface, width: 1.5),
                            ),
                            child: Icon(Icons.check, size: 11, color: colors.bubbleMineFg),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  icon.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on ? icon.swatch : colors.textSecondary,
                    fontSize: 11,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.colors,
    this.options = const ['everyone', 'friends', 'nobody'],
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final QcColors colors;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: colors.textPrimary))),
          DropdownButton<String>(
            value: options.contains(value) ? value : options.first,
            dropdownColor: colors.elevated,
            underline: const SizedBox.shrink(),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o, style: TextStyle(color: colors.textSecondary))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
