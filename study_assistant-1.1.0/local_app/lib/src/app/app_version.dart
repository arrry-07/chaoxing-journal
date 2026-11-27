class AppVersion {
  const AppVersion._();

  static const name = '1.93.0';
  static const code = 136;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
