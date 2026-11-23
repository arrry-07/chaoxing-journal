class AppVersion {
  const AppVersion._();

  static const name = '1.8.26';
  static const code = 120;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
