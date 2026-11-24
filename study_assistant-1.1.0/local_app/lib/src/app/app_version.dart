class AppVersion {
  const AppVersion._();

  static const name = '1.8.28';
  static const code = 122;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
