class AppVersion {
  const AppVersion._();

  static const name = '1.8.26-dev.2';
  static const code = 116;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
