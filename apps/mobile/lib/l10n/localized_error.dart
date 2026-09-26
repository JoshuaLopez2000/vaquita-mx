import 'package:vaquita_mx/l10n/app_localizations.dart';

String localizedError(AppLocalizations l10n, String error) => switch (error) {
      'server_unavailable' => l10n.serverUnavailable,
      'server_request_failed' => l10n.serverRequestFailed,
      'request_failed' => l10n.requestFailed,
      _ => error,
    };
