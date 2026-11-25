class AppVersion {
  const AppVersion._();

  static const name = '1.8.33';
  static const code = 126;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
