class AppVersion {
  const AppVersion._();

  static const name = '1.90.2';
  static const code = 129;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
