class AppVersion {
  const AppVersion._();

  static const name = '1.91.0';
  static const code = 131;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
