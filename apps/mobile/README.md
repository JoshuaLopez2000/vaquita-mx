# Vaquita MX Android client

Flutter/Material 3 client for Vaquita MX. The current screen establishes the visual baseline and displays the configured API origin.

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` reaches the host machine from the Android emulator. For a physical device or remote environment, provide the reachable HTTPS API URL at build time. Do not pass secrets through `--dart-define`.
