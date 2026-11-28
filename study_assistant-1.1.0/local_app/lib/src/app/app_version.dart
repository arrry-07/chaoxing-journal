class AppVersion {
  const AppVersion._();

  static const name = '1.93.1';
  static const code = 137;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
