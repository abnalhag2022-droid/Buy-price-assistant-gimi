import 'package:flutter/material.dart';

import 'tokens.dart';

/// Colours with a meaning beyond the Material roles: purchases, sales,
/// warnings and success, each with a container and an "on" colour that keep
/// at least 4.5:1 contrast in light and dark themes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.purchase,
    required this.onPurchase,
    required this.purchaseContainer,
    required this.onPurchaseContainer,
    required this.sale,
    required this.onSale,
    required this.saleContainer,
    required this.onSaleContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.favorite,
  });

  final Color purchase, onPurchase, purchaseContainer, onPurchaseContainer;
  final Color sale, onSale, saleContainer, onSaleContainer;
  final Color warningContainer, onWarningContainer;
  final Color successContainer, onSuccessContainer;
  final Color infoContainer, onInfoContainer;
  final Color favorite;

  static const AppPalette light = AppPalette(
    purchase: Color(0xFF1E5AA8),
    onPurchase: Colors.white,
    purchaseContainer: Color(0xFFE7F0FB),
    onPurchaseContainer: Color(0xFF0F3B73),
    sale: Color(0xFF1B7A4C),
    onSale: Colors.white,
    saleContainer: Color(0xFFE4F4EA),
    onSaleContainer: Color(0xFF0D4B2E),
    warningContainer: Color(0xFFFFF3D3),
    onWarningContainer: Color(0xFF5C4100),
    successContainer: Color(0xFFE4F4EA),
    onSuccessContainer: Color(0xFF0D4B2E),
    infoContainer: Color(0xFFE8EEF7),
    onInfoContainer: Color(0xFF18365F),
    favorite: Color(0xFFB07A00),
  );

  static const AppPalette dark = AppPalette(
    purchase: Color(0xFF8DB7F0),
    onPurchase: Color(0xFF0B2545),
    purchaseContainer: Color(0xFF1A2E4A),
    onPurchaseContainer: Color(0xFFD6E6FA),
    sale: Color(0xFF7FD3A6),
    onSale: Color(0xFF00391F),
    saleContainer: Color(0xFF15382A),
    onSaleContainer: Color(0xFFCDEFDC),
    warningContainer: Color(0xFF3D3014),
    onWarningContainer: Color(0xFFFFE2A1),
    successContainer: Color(0xFF15382A),
    onSuccessContainer: Color(0xFFCDEFDC),
    infoContainer: Color(0xFF1C2838),
    onInfoContainer: Color(0xFFD3E1F5),
    favorite: BrandColors.gold,
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Figures with equal width so prices line up in lists.
const List<FontFeature> tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

abstract final class AppTheme {
  static ThemeData light() => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: BrandColors.navy,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFD7E3F5),
          onPrimaryContainer: Color(0xFF0B2545),
          secondary: BrandColors.gold,
          onSecondary: Color(0xFF3D2C00),
          secondaryContainer: Color(0xFFFFEDC2),
          onSecondaryContainer: Color(0xFF4A3500),
          tertiary: Color(0xFF1B7A4C),
          onTertiary: Colors.white,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          errorContainer: Color(0xFFFDECEA),
          onErrorContainer: Color(0xFF7A1712),
          surface: Colors.white,
          onSurface: Color(0xFF1A1F27),
          onSurfaceVariant: Color(0xFF515C6B),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Color(0xFFF5F7FA),
          surfaceContainer: Color(0xFFEFF2F6),
          surfaceContainerHigh: Color(0xFFE9EDF2),
          surfaceContainerHighest: Color(0xFFE3E8EE),
          outline: Color(0xFF7D8896),
          outlineVariant: Color(0xFFDDE3EA),
          inverseSurface: Color(0xFF2B313A),
          onInverseSurface: Color(0xFFEFF2F6),
        ),
        AppPalette.light,
        scaffold: const Color(0xFFF5F7FA),
      );

  static ThemeData dark() => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFFA9C7F2),
          onPrimary: Color(0xFF0B2545),
          primaryContainer: Color(0xFF233F66),
          onPrimaryContainer: Color(0xFFD7E3F5),
          secondary: BrandColors.gold,
          onSecondary: Color(0xFF3D2C00),
          secondaryContainer: Color(0xFF4A3A10),
          onSecondaryContainer: Color(0xFFFFE2A1),
          tertiary: Color(0xFF7FD3A6),
          onTertiary: Color(0xFF00391F),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          errorContainer: Color(0xFF4A1C1A),
          onErrorContainer: Color(0xFFFFDAD6),
          surface: Color(0xFF161C24),
          onSurface: Color(0xFFE6EAF0),
          onSurfaceVariant: Color(0xFFAAB4C0),
          surfaceContainerLowest: Color(0xFF0F141B),
          surfaceContainerLow: Color(0xFF131920),
          surfaceContainer: Color(0xFF1B222C),
          surfaceContainerHigh: Color(0xFF212934),
          surfaceContainerHighest: Color(0xFF28313D),
          outline: Color(0xFF8893A1),
          outlineVariant: Color(0xFF2E3946),
          inverseSurface: Color(0xFFE6EAF0),
          onInverseSurface: Color(0xFF1A1F27),
        ),
        AppPalette.dark,
        scaffold: const Color(0xFF0F141B),
      );

  static ThemeData _build(ColorScheme scheme, AppPalette palette, {required Color scaffold}) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
    const buttonSize = Size(64, Sizes.touchTarget);
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: scheme.outlineVariant)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
        border: OutlineInputBorder(borderRadius: Radii.tile, borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: Radii.tile, borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: Radii.tile, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: Radii.tile, borderSide: BorderSide(color: scheme.error)),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, side: BorderSide(color: scheme.outline)),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, Sizes.touchTarget), shape: buttonShape)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      ),
      chipTheme: base.chipTheme.copyWith(shape: const RoundedRectangleBorder(borderRadius: Radii.chip)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(minimumSize: const Size(48, Sizes.touchTarget)),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: Space.sm,
        iconColor: scheme.onSurfaceVariant,
        shape: const RoundedRectangleBorder(borderRadius: Radii.tile),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      navigationDrawerTheme: NavigationDrawerThemeData(backgroundColor: scheme.surface),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl))),
    );
  }
}
