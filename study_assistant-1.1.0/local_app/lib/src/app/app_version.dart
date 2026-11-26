class AppVersion {
  const AppVersion._();

  static const name = '1.90.3';
  static const code = 130;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
