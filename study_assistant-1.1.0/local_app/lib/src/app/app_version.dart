class AppVersion {
  const AppVersion._();

  static const name = '1.8.27';
  static const code = 121;

  static String get releaseName => name.split('-').first;
  static String get display => '$name ($code)';
}
