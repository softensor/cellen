import 'package:flutter/material.dart';

class AppTheme {
  // Core palette
  static const Color primary = Color(0xFF1A56DB);       // Professional blue
  static const Color primaryLight = Color(0xFFEBF5FF);  // Very light blue tint
  static const Color secondary = Color(0xFF0EA5E9);      // Sky accent
  static const Color success = Color(0xFF057A55);
  static const Color warning = Color(0xFFB45309);
  static const Color danger = Color(0xFFE02424);
  static const Color textPrimary = Color(0xFF111928);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color surface = Color(0xFFF9FAFB);

  static ThemeData get light {
    const cs = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE0F2FE),
      onSecondaryContainer: Color(0xFF0369A1),
      error: danger,
      onError: Colors.white,
      errorContainer: Color(0xFFFDE8E8),
      onErrorContainer: danger,
      surface: Colors.white,
      onSurface: textPrimary,
      surfaceContainerHighest: surface,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: Color(0xFFF3F4F6),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          fontFamily: 'Roboto',
        ),
        toolbarHeight: 60,
        shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: danger),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(primary),
          foregroundColor: WidgetStatePropertyAll(Colors.white),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)))),
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)))),
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ),
      dividerTheme: const DividerThemeData(
          color: border, thickness: 1, space: 0),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primaryLight,
        selectedIconTheme: IconThemeData(color: primary, size: 22),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 22),
        selectedLabelTextStyle: TextStyle(
            color: primary, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(
            color: textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
        labelType: NavigationRailLabelType.all,
        minWidth: 72,
        elevation: 0,
        groupAlignment: -1,
      ),
    );
  }

  // Minimal dark theme (keeps the app functional in dark mode)
  static ThemeData get dark {
    final cs = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
    );
  }

  // Status chip helpers
  static Color statusBg(String status) => switch (status) {
    'present' => const Color(0xFFDEF7EC),
    'absent' => const Color(0xFFFDE8E8),
    'late' => const Color(0xFFFEF3C7),
    'excused' => const Color(0xFFE0F2FE),
    'paid' => const Color(0xFFDEF7EC),
    'pending' => const Color(0xFFFEF3C7),
    'overdue' => const Color(0xFFFDE8E8),
    'minor' => const Color(0xFFFEF3C7),
    'moderate' => const Color(0xFFFFEDD5),
    'serious' => const Color(0xFFFDE8E8),
    _ => const Color(0xFFF3F4F6),
  };

  static Color statusText(String status) => switch (status) {
    'present' => const Color(0xFF03543F),
    'absent' => const Color(0xFF9B1C1C),
    'late' => const Color(0xFF92400E),
    'excused' => const Color(0xFF1E40AF),
    'paid' => const Color(0xFF03543F),
    'pending' => const Color(0xFF92400E),
    'overdue' => const Color(0xFF9B1C1C),
    'minor' => const Color(0xFF92400E),
    'moderate' => const Color(0xFFC2410C),
    'serious' => const Color(0xFF9B1C1C),
    _ => const Color(0xFF374151),
  };

  static String statusLabel(String status) => switch (status) {
    'present' => 'Presente',
    'absent' => 'Ausente',
    'late' => 'Tarde',
    'excused' => 'Justificado',
    'paid' => 'Pago',
    'pending' => 'Pendente',
    'overdue' => 'Em Atraso',
    'minor' => 'Leve',
    'moderate' => 'Moderada',
    'serious' => 'Grave',
    _ => status,
  };
}
