class AppVersion {
  const AppVersion._();

  static const name = '1.8.31';
  static const code = 124;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
