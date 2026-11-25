import 'dart:async';

import 'package:flutter/services.dart';

/// Parses `vaquitamx://payment-requests/{id}` deep links into the target
/// payment request identifier, or returns `null` for unrecognized links.
String? parsePaymentRequestDeepLink(String? rawUri) {
  if (rawUri == null) return null;
  final trimmed = rawUri.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'vaquitamx') return null;
  if (uri.host.toLowerCase() != 'payment-requests') return null;
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.length != 1) return null;
  final id = segments.single.trim();
  if (id.isEmpty || RegExp(r'\s').hasMatch(id)) return null;
  return id;
}

abstract class DeepLinkSource {
  Future<String?> getInitialLink();
  Stream<String> get links;
  void dispose();
}

class PlatformDeepLinkSource implements DeepLinkSource {
  PlatformDeepLinkSource({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final raw = call.arguments;
        if (raw is String && raw.trim().isNotEmpty && !_controller.isClosed) {
          _controller.add(raw);
        }
      }
    });
  }

  static const channelName = 'mx.vaquita.vaquita_mx/deep_links';

  final MethodChannel _channel;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  Stream<String> get links => _controller.stream;

  @override
  Future<String?> getInitialLink() async {
    try {
      final raw = await _channel.invokeMethod<String>('getInitialLink');
      if (raw == null || raw.trim().isEmpty) return null;
      return raw;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_controller.close());
  }
}
