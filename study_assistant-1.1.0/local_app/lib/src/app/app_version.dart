class AppVersion {
  const AppVersion._();

  static const name = '1.92.0';
  static const code = 132;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
