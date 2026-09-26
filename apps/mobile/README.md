# Vaquita MX Flutter client

Flutter/Material 3 client for Vaquita MX. The current screen establishes the visual baseline and displays the configured API origin.

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

For the web client, start the API and run:

```bash
flutter run -d chrome --web-port=3000
```

The browser defaults to `http://localhost:8080`; Android defaults to `http://10.0.2.2:8080`. Override either with `--dart-define=API_BASE_URL=https://api.example.com`. The API's `ALLOWED_ORIGINS` must include the web origin (for the command above, `http://localhost:3000`). Do not pass secrets through `--dart-define`.
