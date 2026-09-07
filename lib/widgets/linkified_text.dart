import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/qc_theme.dart';
import '../utils/linkify.dart';

/// Renders message text with tappable URLs, emails, phones, and @mentions.
class LinkifiedText extends StatelessWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.mentionStyle,
    required this.colors,
  });

  final String text;
  final TextStyle baseStyle;
  final TextStyle mentionStyle;
  final QcColors colors;

  Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tokens = linkifyText(text);
    final spans = <InlineSpan>[];

    for (final tok in tokens) {
      switch (tok.type) {
        case 'mention':
          spans.add(TextSpan(text: tok.value, style: mentionStyle));
        case 'url':
          final href = toHref(tok.value);
          if (isSafeHttpUrl(href)) {
            spans.add(
              TextSpan(
                text: tok.value,
                style: baseStyle.copyWith(
                  color: colors.accentCyan,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _open(Uri.parse(href)),
              ),
            );
          } else {
            spans.add(TextSpan(text: tok.value));
          }
        case 'email':
          spans.add(
            TextSpan(
              text: tok.value,
              style: baseStyle.copyWith(
                color: colors.accentCyan,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open(Uri(scheme: 'mailto', path: tok.value)),
            ),
          );
        case 'phone':
          spans.add(
            TextSpan(
              text: tok.value,
              style: baseStyle.copyWith(
                color: colors.accentCyan,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await Clipboard.setData(ClipboardData(text: tok.value));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Phone number copied')),
                    );
                  }
                  final digits = tok.value.replaceAll(RegExp(r'[^\d+]'), '');
                  await _open(Uri(scheme: 'tel', path: digits));
                },
            ),
          );
        default:
          spans.add(TextSpan(text: tok.value));
      }
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}
