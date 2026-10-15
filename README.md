# APM Mobile

Aplikasi Android untuk **APM (Asset Performance Monitoring)** PT Petrokimia Gresik.
Backend: repo `apm` (Laravel 10) — API khusus mobile di `routes/api.mobile.php`,
prefix **`/api/mobile/v1`** (terpisah dari `/api/*` milik PetroVibration dll).

Fokus awal: **Report Workorder** dan **General Data**.

## Status

| Fitur | Status |
|---|---|
| Login OneKey — halaman Keycloak sama dgn web (`/mobile/auth/keycloak/redirect` → `POST /auth/exchange`); sesi ikut Keycloak; logout = end-session | ✅ |
| Daftar workorder + cari + filter Belum/Sudah Report (`GET /workorders`) | ✅ |
| Detail workorder (`GET /workorders/{no_wo}`) + operasi & report | ✅ |
| Form report/konfirmasi WO | ⏳ endpoint mobile belum dibuat |
| General Data | ⏳ endpoint API belum ada di backend |
| Push notification (FCM) | ⏳ |

## Menjalankan

Prasyarat: Flutter stable (`C:\src\flutter\bin` ada di PATH), Android SDK, emulator/HP.

```bash
flutter pub get
cp env/dev.example.json env/dev.json   # lalu isi APP_BASE_URL
flutter run --dart-define-from-file=env/dev.json
```

- `APP_BASE_URL` = alamat server APM yang **diizinkan di Valid Redirect URIs client Keycloak** (sama dengan
  alamat login web dev). Jangan pakai alias localhost emulator Android — Keycloak menolak redirect ke alamat itu.
- `env/dev.json` tidak di-commit (berisi alamat server internal).
- HTTP polos hanya diizinkan di build debug (`android/app/src/debug/AndroidManifest.xml`).

### Troubleshooting

`java.io.IOException: Unable to establish loopback connection` saat build Gradle
→ bug JDK 16+ di Windows bila path TEMP memakai short name (`CPPG03~1`). Set sekali:

```bash
setx JAVA_TOOL_OPTIONS "-Djdk.net.unixdomain.tmpdir=C:\src\jtmp"
```

## Struktur

```
lib/
  core/        config, tema (warna APM web), API client (Dio + token Sanctum)
  features/
    auth/          login, sesi
    home/          beranda + bottom navigation
    workorder/     daftar & detail WO
    general_data/  (placeholder)
    profile/       profil & logout
  router.dart  go_router + redirect auth
```

Warna diambil dari `apm/resources/scss/config/corporate/_variables.scss`
(primary `#45B377`, secondary `#FF7F5D`, body `#FBF7F4`, font Public Sans).
