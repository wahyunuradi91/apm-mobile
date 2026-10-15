import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet diambil dari APM web:
/// resources/scss/config/corporate/_variables.scss
class ApmColors {
  static const primary = Color(0xFF45B377); // $blue → $primary
  static const secondary = Color(0xFFFF7F5D); // $orange → $secondary
  static const success = Color(0xFF3CD188);
  static const info = Color(0xFF0AC7FB);
  static const warning = Color(0xFFE5B700);
  static const danger = Color(0xFFE74C3C);
  static const bodyBg = Color(0xFFFBF7F4);
  static const light = Color(0xFFF3F6F9); // $gray-100
  static const border = Color(0xFFEFF2F7); // $gray-200
  static const muted = Color(0xFF878A99); // $gray-600
  static const dark = Color(0xFF272A3A); // $gray-900
}

ThemeData buildApmTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ApmColors.primary,
    primary: ApmColors.primary,
    onPrimary: Colors.white,
    secondary: ApmColors.secondary,
    onSecondary: Colors.white,
    error: ApmColors.danger,
    surface: Colors.white,
    onSurface: ApmColors.dark,
  );

  // Font web APM = 'Public Sans' ($font-family-primary).
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: GoogleFonts.publicSans().fontFamily,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: ApmColors.dark,
    displayColor: ApmColors.dark,
  );

  const radius = BorderRadius.all(Radius.circular(6));

  return base.copyWith(
    scaffoldBackgroundColor: ApmColors.bodyBg,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ApmColors.dark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black12,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: ApmColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFFCED4DA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFFCED4DA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: ApmColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ApmColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ApmColors.primary.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ApmColors.primary
              : ApmColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? ApmColors.primary
              : ApmColors.muted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: ApmColors.border, space: 1),
  );
}

/// Badge bergaya "badge-soft-*" seperti di APM web.
class SoftBadge extends StatelessWidget {
  const SoftBadge(this.label, {super.key, this.color = ApmColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
