// Splits message text into tokens for clickable mentions, URLs, emails, phones.
// Types: text | mention | url | email | phone

class LinkToken {
  const LinkToken({required this.type, required this.value});
  final String type;
  final String value;
}

final _combinedRe = RegExp(
  r'(@[a-zA-Z0-9_.-]{2,32})|'
  r'''((?:https?:\/\/|www\.)[^\s<>"'')\]]+)|'''
  r'([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|'
  r'(\+?\d[\d\-\s().]{5,}\d)',
);

String _digitsOf(String raw) => raw.replaceAll(RegExp(r'\D'), '');

List<LinkToken> linkifyText(String? text) {
  final input = text ?? '';
  final tokens = <LinkToken>[];
  var last = 0;

  for (final match in _combinedRe.allMatches(input)) {
    if (match.start > last) {
      tokens.add(LinkToken(type: 'text', value: input.substring(last, match.start)));
    }

    final mention = match.group(1);
    final url = match.group(2);
    final email = match.group(3);
    final phone = match.group(4);

    if (mention != null) {
      tokens.add(LinkToken(type: 'mention', value: mention));
    } else if (url != null) {
      var cleaned = url;
      final trailing = RegExp(r'[.,!?;:]+$').firstMatch(cleaned);
      if (trailing != null) {
        cleaned = cleaned.substring(0, trailing.start);
        tokens.add(LinkToken(type: 'url', value: cleaned));
        tokens.add(LinkToken(type: 'text', value: trailing.group(0)!));
      } else {
        tokens.add(LinkToken(type: 'url', value: cleaned));
      }
    } else if (email != null) {
      tokens.add(LinkToken(type: 'email', value: email));
    } else if (phone != null) {
      final digits = _digitsOf(phone);
      if (digits.length >= 7 && digits.length <= 15) {
        tokens.add(LinkToken(type: 'phone', value: phone.trim()));
      } else {
        tokens.add(LinkToken(type: 'text', value: phone));
      }
    }

    last = match.end;
  }

  if (last < input.length) {
    tokens.add(LinkToken(type: 'text', value: input.substring(last)));
  }
  return tokens;
}

String toHref(String url) => url.startsWith('http') ? url : 'https://$url';

bool isSafeHttpUrl(String href) {
  try {
    final uri = Uri.parse(href);
    return uri.scheme == 'http' || uri.scheme == 'https';
  } catch (_) {
    return false;
  }
}
