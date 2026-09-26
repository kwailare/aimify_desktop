import 'dart:io';

/// Best-effort label for this computer, sent as `deviceName` on login so the
/// person sees something friendlier than a bare `User-Agent` under
/// Settings → Signed-in devices on the website. Never throws — falls back
/// to a generic label if the OS won't say.
String currentDeviceName() {
  try {
    final hostname = Platform.localHostname.trim();
    if (hostname.isEmpty) return _fallbackName;
    // The API caps this at 80 characters.
    return hostname.length > 80 ? hostname.substring(0, 80) : hostname;
  } catch (_) {
    return _fallbackName;
  }
}

String get _fallbackName {
  if (Platform.isWindows) return 'Windows PC';
  if (Platform.isMacOS) return 'Mac';
  if (Platform.isLinux) return 'Linux PC';
  return 'Aimify Desktop';
}
