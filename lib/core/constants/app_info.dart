/// Keep in sync with the `version:` line in `pubspec.yaml` — there's no
/// package_info_plus dependency pulled in just to read it back at runtime.
class AppInfo {
  AppInfo._();

  static const String version = '1.0.0';
}
