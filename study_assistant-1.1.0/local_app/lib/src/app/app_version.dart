class AppVersion {
  const AppVersion._();

  static const name = '1.8.23-dev.1';
  static const code = 90;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
