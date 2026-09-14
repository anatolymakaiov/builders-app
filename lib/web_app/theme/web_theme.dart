import 'package:flutter/material.dart';

class WebTheme {
  static const deep = Color(0xFF142B38);
  static const ink = Color(0xFF20343F);
  static const muted = Color(0xFF667781);
  static const subtleText = Color(0xFF87949C);
  static const green = Color(0xFF21864A);
  static const greenHover = Color(0xFF196F3C);
  static const greenSoft = Color(0xFFE8F4EC);
  static const blueprint = Color(0xFF4B82A1);
  static const border = Color(0xFFDDE4E8);
  static const borderStrong = Color(0xFFC3CDD3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF6F8F9);
  static const elevatedSurface = Color(0xFFFBFCFC);
  static const page = Color(0xFFF0F3F5);
  static const selected = Color(0xFFE9F3ED);
  static const success = Color(0xFF21864A);
  static const warning = Color(0xFFB36B00);
  static const warningSoft = Color(0xFFFFF4DE);
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFFECEA);
  static const info = Color(0xFF326B8C);
  static const infoSoft = Color(0xFFEAF3F8);

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: green,
      onPrimary: Colors.white,
      primaryContainer: greenSoft,
      onPrimaryContainer: deep,
      secondary: blueprint,
      onSecondary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      outline: borderStrong,
      outlineVariant: border,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      fontFamily: null,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    return base.copyWith(
      textTheme: const TextTheme(
        headlineLarge: WebTypography.pageTitle,
        headlineMedium: WebTypography.pageTitle,
        headlineSmall: WebTypography.sectionTitle,
        titleLarge: WebTypography.sectionTitle,
        titleMedium: WebTypography.panelTitle,
        titleSmall: WebTypography.cardTitle,
        bodyLarge: WebTypography.bodyLarge,
        bodyMedium: WebTypography.body,
        bodySmall: WebTypography.metadata,
        labelLarge: WebTypography.button,
        labelMedium: WebTypography.label,
        labelSmall: WebTypography.caption,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebSpacing.md,
          vertical: 14,
        ),
        labelStyle: WebTypography.label.copyWith(color: muted),
        hintStyle: WebTypography.body.copyWith(color: subtleText),
        helperStyle: WebTypography.caption.copyWith(color: muted),
        errorStyle: WebTypography.caption.copyWith(color: danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadii.input),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadii.input),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadii.input),
          borderSide: const BorderSide(color: green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebRadii.input),
          borderSide: const BorderSide(color: danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: WebSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebRadii.button),
          ),
          textStyle: WebTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: WebSpacing.lg),
          side: const BorderSide(color: borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebRadii.button),
          ),
          textStyle: WebTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: WebSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebRadii.button),
          ),
          textStyle: WebTypography.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(42, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebRadii.button),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceAlt,
        selectedColor: selected,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadii.tag),
        ),
        labelStyle: WebTypography.label,
        padding: const EdgeInsets.symmetric(horizontal: WebSpacing.xs),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(80, 42)),
          textStyle: const WidgetStatePropertyAll(WebTypography.button),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WebRadii.button),
            ),
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: borderStrong)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? selected : surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? green : ink,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      listTileTheme: const ListTileThemeData(
        textColor: ink,
        iconColor: muted,
        selectedColor: green,
        selectedTileColor: selected,
        contentPadding: EdgeInsets.symmetric(horizontal: WebSpacing.md),
        minVerticalPadding: WebSpacing.sm,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadii.panel),
          side: const BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadii.panel),
        ),
        titleTextStyle: WebTypography.sectionTitle,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadii.card),
          side: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: deep,
        contentTextStyle: WebTypography.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebRadii.button),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: deep,
          borderRadius: BorderRadius.circular(WebRadii.input),
        ),
        textStyle: WebTypography.caption.copyWith(color: Colors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(WebRadii.tag),
        thickness: const WidgetStatePropertyAll(8),
        thumbVisibility: const WidgetStatePropertyAll(false),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ? borderStrong : border,
        ),
      ),
      focusColor: greenSoft,
      hoverColor: deep.withValues(alpha: 0.045),
      highlightColor: deep.withValues(alpha: 0.035),
    );
  }
}

class WebSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
  static const huge = 48.0;
}

class WebRadii {
  static const input = 6.0;
  static const button = 6.0;
  static const panel = 8.0;
  static const card = 8.0;
  static const avatar = 999.0;
  static const tag = 999.0;
}

class WebShadows {
  static const subtle = <BoxShadow>[
    BoxShadow(
      color: Color(0x100E2430),
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];

  static const elevated = <BoxShadow>[
    BoxShadow(
      color: Color(0x160E2430),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

class WebTypography {
  static const pageTitle = TextStyle(
    color: WebTheme.deep,
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
  static const sectionTitle = TextStyle(
    color: WebTheme.deep,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const panelTitle = TextStyle(
    color: WebTheme.ink,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const cardTitle = TextStyle(
    color: WebTheme.ink,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const bodyLarge = TextStyle(
    color: WebTheme.ink,
    fontSize: 15,
    height: 1.45,
    letterSpacing: 0,
  );
  static const body = TextStyle(
    color: WebTheme.ink,
    fontSize: 14,
    height: 1.4,
    letterSpacing: 0,
  );
  static const metadata = TextStyle(
    color: WebTheme.muted,
    fontSize: 13,
    height: 1.35,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    color: WebTheme.ink,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  static const caption = TextStyle(
    color: WebTheme.muted,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0,
  );
  static const button = TextStyle(
    fontSize: 14,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
}
