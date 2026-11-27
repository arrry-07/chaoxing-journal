class AppVersion {
  const AppVersion._();

  static const name = '1.92.1';
  static const code = 133;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
