class AppVersion {
  const AppVersion._();

  static const name = '1.8.25-dev.5';
  static const code = 113;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
