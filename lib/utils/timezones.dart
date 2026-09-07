/// Common IANA timezones for birthday scheduling (matches web fallback list).
const timezoneOptions = <String>[
  'UTC',
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Sao_Paulo',
  'America/Mexico_City',
  'America/Bogota',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Moscow',
  'Europe/Istanbul',
  'Africa/Cairo',
  'Africa/Lagos',
  'Africa/Johannesburg',
  'Africa/Nairobi',
  'Asia/Dubai',
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Bangkok',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Singapore',
  'Asia/Jakarta',
  'Australia/Perth',
  'Australia/Sydney',
  'Pacific/Auckland',
];

String detectDeviceTimezone() {
  try {
    return DateTime.now().timeZoneName;
  } catch (_) {
    return 'UTC';
  }
}

/// Prefer a known IANA id; fall back to UTC if the device zone isn't in the list.
String pickDefaultTimezone() {
  final device = detectDeviceTimezone();
  if (timezoneOptions.contains(device)) return device;
  // Common Android abbreviations → IANA
  const map = {
    'PKT': 'Asia/Karachi',
    'IST': 'Asia/Kolkata',
    'PST': 'America/Los_Angeles',
    'PDT': 'America/Los_Angeles',
    'EST': 'America/New_York',
    'EDT': 'America/New_York',
    'GMT': 'Europe/London',
    'BST': 'Europe/London',
  };
  return map[device] ?? 'UTC';
}
