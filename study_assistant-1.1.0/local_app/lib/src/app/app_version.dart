class AppVersion {
  const AppVersion._();

  static const name = '1.8.24';
  static const code = 108;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
