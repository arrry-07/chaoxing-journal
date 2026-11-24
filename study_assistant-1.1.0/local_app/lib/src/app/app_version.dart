class AppVersion {
  const AppVersion._();

  static const name = '1.8.29';
  static const code = 123;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
