/// Fixed Odoo server address. Change this one line to point to another server.
const String kOdooUrl = 'https://odoo-199087-0.cloudclusters.net';

/// Reasons offered when adjusting stock (recorded in the Odoo adjustment name).
const List<String> kAdjustReasons = [
  'Miscount',
  'Damaged',
  'Found stock',
  'Expired / wasted',
  'Other',
];

/// Shown in Menu > About. Keep in sync with `version:` in pubspec.yaml.
const String kAppVersion = '1.1.0';
const String kDeveloper = 'Haseeb Kakkodi';
