class AppVersion {
  const AppVersion._();

  static const name = '1.8.25';
  static const code = 114;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
