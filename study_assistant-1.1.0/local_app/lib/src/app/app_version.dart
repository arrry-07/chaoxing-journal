class AppVersion {
  const AppVersion._();

  static const name = '1.8.23-dev.6';
  static const code = 95;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
