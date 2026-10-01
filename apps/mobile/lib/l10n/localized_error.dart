import 'package:vaquita_mx/l10n/app_localizations.dart';

String localizedError(AppLocalizations l10n, String error,
        {String? fallback}) =>
    switch (error) {
      'server_unavailable' => l10n.serverUnavailable,
      'server_request_failed' => l10n.serverRequestFailed,
      'request_failed' => l10n.requestFailed,
      'internal_error' => l10n.serverRequestFailed,
      'service_unavailable' => l10n.serverUnavailable,
      _ => fallback ?? l10n.requestFailed,
    };
