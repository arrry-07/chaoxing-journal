class AppVersion {
  const AppVersion._();

  static const name = '1.8.32';
  static const code = 125;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
