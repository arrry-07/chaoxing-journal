class AppVersion {
  const AppVersion._();

  static const name = '1.8.23-dev.4';
  static const code = 93;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
