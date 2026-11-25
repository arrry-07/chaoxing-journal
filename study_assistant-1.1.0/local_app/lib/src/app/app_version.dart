class AppVersion {
  const AppVersion._();

  static const name = '1.90.0';
  static const code = 127;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
