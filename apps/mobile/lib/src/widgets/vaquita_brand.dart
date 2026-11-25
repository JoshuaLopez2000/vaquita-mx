import 'package:flutter/material.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';

/// Geometric Vaquita MX emblem: shared alcancía / vaquita silhouette paired
/// with a warm gold coin dropping into a ledger slot.
class VaquitaLogoMark extends StatelessWidget {
  const VaquitaLogoMark({
    this.size = 72,
    this.semanticLabel,
    super.key,
  });

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final vColors = VaquitaColors.of(context);
    final emblem = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _VaquitaEmblemPainter(
          gradientStart: vColors.heroStart,
          gradientEnd: vColors.heroEnd,
          accentRing: vColors.heroAccent.withValues(alpha: 0.28),
        ),
      ),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: emblem);
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: emblem,
    );
  }
}

class _VaquitaEmblemPainter extends CustomPainter {
  const _VaquitaEmblemPainter({
    required this.gradientStart,
    required this.gradientEnd,
    required this.accentRing,
  });

  final Color gradientStart;
  final Color gradientEnd;
  final Color accentRing;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final radius = Radius.circular(w * 0.28);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // Medallion base
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientStart, gradientEnd],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    // Subtle inner hairline border
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..color = accentRing;
    canvas.drawRRect(rrect.deflate(w * 0.03), ringPaint);

    // Coin slot at top
    final slotPaint = Paint()..color = const Color(0xFF042620);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.26),
          width: w * 0.28,
          height: h * 0.045,
        ),
        Radius.circular(w * 0.03),
      ),
      slotPaint,
    );

    // Gold MXN coin entering the shared pot ("la vaquita")
    final coinCenter = Offset(w * 0.5, h * 0.21);
    final coinPaint = Paint()..color = const Color(0xFFF5B841);
    canvas.drawCircle(coinCenter, w * 0.105, coinPaint);
    final coinInnerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..color = const Color(0xFFFFDF94);
    canvas.drawCircle(coinCenter, w * 0.068, coinInnerPaint);

    // Geometric horns
    final hornPaint = Paint()
      ..color = const Color(0xFFFDFBF7)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.065;
    final leftHorn = Path()
      ..moveTo(w * 0.34, h * 0.44)
      ..quadraticBezierTo(w * 0.25, h * 0.34, w * 0.29, h * 0.27);
    final rightHorn = Path()
      ..moveTo(w * 0.66, h * 0.44)
      ..quadraticBezierTo(w * 0.75, h * 0.34, w * 0.71, h * 0.27);
    canvas.drawPath(leftHorn, hornPaint);
    canvas.drawPath(rightHorn, hornPaint);

    // Ears
    final creamPaint = Paint()..color = const Color(0xFFFDFBF7);
    canvas.save();
    canvas.translate(w * 0.24, h * 0.49);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: w * 0.16,
        height: h * 0.095,
      ),
      creamPaint,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(w * 0.76, h * 0.49);
    canvas.rotate(0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: w * 0.16,
        height: h * 0.095,
      ),
      creamPaint,
    );
    canvas.restore();

    // Friendly geometric vaquita head
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.58),
          width: w * 0.48,
          height: h * 0.40,
        ),
        Radius.circular(w * 0.18),
      ),
      creamPaint,
    );

    // Subtle spot on forehead
    final spotPaint = Paint()..color = const Color(0xFF0B6B5A);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.60, h * 0.46),
        width: w * 0.13,
        height: h * 0.10,
      ),
      spotPaint,
    );

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFF073B32);
    canvas.drawCircle(Offset(w * 0.40, h * 0.53), w * 0.028, eyePaint);
    canvas.drawCircle(Offset(w * 0.60, h * 0.53), w * 0.028, eyePaint);

    // Warm terracotta/sand snout
    final snoutPaint = Paint()..color = const Color(0xFFF3D5C0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.67),
          width: w * 0.34,
          height: h * 0.17,
        ),
        Radius.circular(w * 0.09),
      ),
      snoutPaint,
    );

    // Nostrils
    final nostrilPaint = Paint()..color = const Color(0xFF8C4A27);
    canvas.drawCircle(Offset(w * 0.44, h * 0.67), w * 0.022, nostrilPaint);
    canvas.drawCircle(Offset(w * 0.56, h * 0.67), w * 0.022, nostrilPaint);
  }

  @override
  bool shouldRepaint(covariant _VaquitaEmblemPainter oldDelegate) {
    return oldDelegate.gradientStart != gradientStart ||
        oldDelegate.gradientEnd != gradientEnd ||
        oldDelegate.accentRing != accentRing;
  }
}

/// Consistent empty-state card/container used across tabs and detail views.
class VaquitaEmptyState extends StatelessWidget {
  const VaquitaEmptyState({
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.inCard = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: inCard ? 24 : 32,
        vertical: inCard ? 28 : 36,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 30,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
    if (!inCard) return content;
    return Card(child: content);
  }
}

/// Branded launch & startup-error screen that matches the native splash
/// background and icon placement so frame 1 transitions seamlessly.
class VaquitaBootstrapScreen extends StatelessWidget {
  const VaquitaBootstrapScreen({
    required this.appTitle,
    required this.loadingLabel,
    this.errorTitle,
    this.errorDescription,
    this.errorDetail,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  final String appTitle;
  final String loadingLabel;
  final String? errorTitle;
  final String? errorDescription;
  final String? errorDetail;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasError = errorDetail != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VaquitaLogoMark(
                    size: 88,
                    semanticLabel: appTitle,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    appTitle.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 2.2,
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!hasError) ...[
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        semanticsLabel: loadingLabel,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      loadingLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    Card(
                      color: colors.errorContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 32,
                              color: colors.onErrorContainer,
                            ),
                            const SizedBox(height: 10),
                            if (errorTitle != null)
                              Text(
                                errorTitle!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            if (errorDescription != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                errorDescription!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              errorDetail!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onErrorContainer
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                            if (onRetry != null && retryLabel != null) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                key: const Key('retry-startup-button'),
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(retryLabel!),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
