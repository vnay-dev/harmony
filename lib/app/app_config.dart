/// Application-wide configuration constants.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Harmony';
  static const String description = 'A Shruti app (pitch drone) for everyone.';

  /// When `true`, Home shows Find My Shruti / Assist Mode.
  ///
  /// Set to `false` for the initial Shruti-only launch. Flip to `true` to
  /// restore the existing Find My Shruti entry point without rebuilding it.
  ///
  /// Platform mic / speech declarations stay in the Android and iOS manifests
  /// while this flag is `false` so Assist Mode can be re-enabled without a
  /// native permission rewrite. Runtime mic/speech access is still only
  /// requested when Assist Mode starts capture — Home drone never opens the mic.
  static const bool enableFindMyShruti = false;
}
