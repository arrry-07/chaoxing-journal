class AppVersion {
  const AppVersion._();

  static const name = '1.90.1';
  static const code = 128;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
