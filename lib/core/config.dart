/// Konfigurasi runtime aplikasi.
///
/// Alamat server APM diisi lewat `--dart-define`, contoh:
///   flutter run --dart-define-from-file=env/dev.json   (salin dari env/dev.example.json)
///
/// Harus alamat yang terdaftar di Valid Redirect URIs client Keycloak APM (sama seperti
/// alamat yang dipakai login web), karena login OneKey berjalan lewat server ini.
class AppConfig {
  static const appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: '',
  );

  static const apiBaseUrl = '$appBaseUrl/api/mobile/v1';

  /// Halaman yang memulai login OneKey (routes/web.php → MobileKeycloakController).
  static const loginUrl = '$appBaseUrl/mobile/auth/keycloak/redirect';

  /// Skema deep link hasil login (lihat AndroidManifest + MobileAuthService::APP_CALLBACK).
  static const callbackScheme = 'apmmobile';
}
