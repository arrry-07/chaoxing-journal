class AppVersion {
  const AppVersion._();

  static const name = '1.8.23-dev.5';
  static const code = 94;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
