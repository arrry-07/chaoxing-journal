class AppVersion {
  const AppVersion._();

  static const name = '1.92.4';
  static const code = 135;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
