import 'package:flutter/material.dart';

@immutable
class VaquitaColors extends ThemeExtension<VaquitaColors> {
  const VaquitaColors({
    required this.positive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.negative,
    required this.negativeContainer,
    required this.onNegativeContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.heroAccent,
    required this.cardBorder,
  });

  final Color positive;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color negative;
  final Color negativeContainer;
  final Color onNegativeContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color heroStart;
  final Color heroEnd;
  final Color onHero;
  final Color heroAccent;
  final Color cardBorder;

  static const light = VaquitaColors(
    positive: Color(0xFF0A6E50),
    positiveContainer: Color(0xFFD9F3E8),
    onPositiveContainer: Color(0xFF053827),
    negative: Color(0xFFB3362A),
    negativeContainer: Color(0xFFFCE8E5),
    onNegativeContainer: Color(0xFF4A100A),
    warning: Color(0xFF8A5600),
    warningContainer: Color(0xFFFFEFCE),
    onWarningContainer: Color(0xFF382000),
    heroStart: Color(0xFF0B6B5A),
    heroEnd: Color(0xFF063D34),
    onHero: Color(0xFFFFFFFF),
    heroAccent: Color(0xFF8BF3DB),
    cardBorder: Color(0xFFE0E4DE),
  );

  static const dark = VaquitaColors(
    positive: Color(0xFF6FE3BA),
    positiveContainer: Color(0xFF113B2D),
    onPositiveContainer: Color(0xFFBFF8E2),
    negative: Color(0xFFFFB4AB),
    negativeContainer: Color(0xFF4A1C17),
    onNegativeContainer: Color(0xFFFFDAD5),
    warning: Color(0xFFFFCA63),
    warningContainer: Color(0xFF3E2700),
    onWarningContainer: Color(0xFFFFE6B3),
    heroStart: Color(0xFF145347),
    heroEnd: Color(0xFF0B2D26),
    onHero: Color(0xFFECFAF6),
    heroAccent: Color(0xFF63DAC3),
    cardBorder: Color(0xFF273631),
  );

  static VaquitaColors of(BuildContext context) {
    return Theme.of(context).extension<VaquitaColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  VaquitaColors copyWith({
    Color? positive,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? negative,
    Color? negativeContainer,
    Color? onNegativeContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? heroStart,
    Color? heroEnd,
    Color? onHero,
    Color? heroAccent,
    Color? cardBorder,
  }) {
    return VaquitaColors(
      positive: positive ?? this.positive,
      positiveContainer: positiveContainer ?? this.positiveContainer,
      onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
      negative: negative ?? this.negative,
      negativeContainer: negativeContainer ?? this.negativeContainer,
      onNegativeContainer: onNegativeContainer ?? this.onNegativeContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      onHero: onHero ?? this.onHero,
      heroAccent: heroAccent ?? this.heroAccent,
      cardBorder: cardBorder ?? this.cardBorder,
    );
  }

  @override
  VaquitaColors lerp(ThemeExtension<VaquitaColors>? other, double t) {
    if (other is! VaquitaColors) return this;
    return VaquitaColors(
      positive: Color.lerp(positive, other.positive, t)!,
      positiveContainer:
          Color.lerp(positiveContainer, other.positiveContainer, t)!,
      onPositiveContainer:
          Color.lerp(onPositiveContainer, other.onPositiveContainer, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      negativeContainer:
          Color.lerp(negativeContainer, other.negativeContainer, t)!,
      onNegativeContainer:
          Color.lerp(onNegativeContainer, other.onNegativeContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      heroAccent: Color.lerp(heroAccent, other.heroAccent, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }
}

abstract final class VaquitaTheme {
  static const Color brandSeed = Color(0xFF0B6B5A);
  static const Color lightCanvas = Color(0xFFF6F5F0);
  static const Color darkCanvas = Color(0xFF0F1513);

  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle money(TextStyle? base, {Color? color, FontWeight? weight}) {
    final resolved = base ?? const TextStyle();
    return resolved.copyWith(
      color: color ?? resolved.color,
      fontWeight: weight ?? resolved.fontWeight ?? FontWeight.w800,
      fontFeatures: tabularFigures,
    );
  }

  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.light,
    );
    final colorScheme = baseScheme.copyWith(
      primary: const Color(0xFF0B6B5A),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFD6F2EA),
      onPrimaryContainer: const Color(0xFF052E26),
      secondary: const Color(0xFF42635B),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFDCE7E3),
      onSecondaryContainer: const Color(0xFF122823),
      tertiary: const Color(0xFF9A5522),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFFFFE4D2),
      onTertiaryContainer: const Color(0xFF381902),
      error: const Color(0xFFB3362A),
      onError: const Color(0xFFFFFFFF),
      errorContainer: const Color(0xFFFCE8E5),
      onErrorContainer: const Color(0xFF4A100A),
      surface: lightCanvas,
      onSurface: const Color(0xFF151D1A),
      onSurfaceVariant: const Color(0xFF46544F),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF0EFE9),
      surfaceContainer: const Color(0xFFEAE9E2),
      surfaceContainerHigh: const Color(0xFFE1E0D8),
      outline: const Color(0xFF72807B),
      outlineVariant: const Color(0xFFD5DBD5),
    );
    return _buildTheme(
      colorScheme: colorScheme,
      tokens: VaquitaColors.light,
      scaffoldBackground: lightCanvas,
    );
  }

  static ThemeData dark() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.dark,
    );
    final colorScheme = baseScheme.copyWith(
      primary: const Color(0xFF63DAC3),
      onPrimary: const Color(0xFF00382E),
      primaryContainer: const Color(0xFF0E4F42),
      onPrimaryContainer: const Color(0xFFC4F7EA),
      secondary: const Color(0xFFAECBC2),
      onSecondary: const Color(0xFF19352E),
      secondaryContainer: const Color(0xFF283E38),
      onSecondaryContainer: const Color(0xFFD1ECE3),
      tertiary: const Color(0xFFFFB68B),
      onTertiary: const Color(0xFF502404),
      tertiaryContainer: const Color(0xFF5C3110),
      onTertiaryContainer: const Color(0xFFFFDCC8),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF4A1C17),
      onErrorContainer: const Color(0xFFFFDAD5),
      surface: darkCanvas,
      onSurface: const Color(0xFFE3EAE6),
      onSurfaceVariant: const Color(0xFFA5B5AF),
      surfaceContainerLowest: const Color(0xFF161F1C),
      surfaceContainerLow: const Color(0xFF1B2522),
      surfaceContainer: const Color(0xFF202C28),
      surfaceContainerHigh: const Color(0xFF283631),
      outline: const Color(0xFF7E9089),
      outlineVariant: const Color(0xFF2B3B35),
    );
    return _buildTheme(
      colorScheme: colorScheme,
      tokens: VaquitaColors.dark,
      scaffoldBackground: darkCanvas,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required VaquitaColors tokens,
    required Color scaffoldBackground,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
    );
    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.38,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color:
                selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        modalBackgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.cardBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
