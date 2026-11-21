class AppVersion {
  const AppVersion._();

  static const name = '1.8.23-dev.11';
  static const code = 100;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
