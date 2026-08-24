import 'package:flutter/material.dart';

/// TRI 디자인 시스템 — "The Quality Operations Console".
///
/// `DESIGN_SYSTEM_KIT.md` / `design-tokens.json`(React·Tailwind·MUI 기준)의
/// 디자인 토큰·색상·타이포·컴포넌트 규칙을 Flutter(Material 3)로 이식한 레이어.
///
/// 3대 원칙:
///  - The Status Must Speak Twice — 합격/불량/경고는 색상 단독 금지, 텍스트·아이콘 동반.
///  - The Blue Means Action — 파란색(primary)은 액션·현재 위치·focus·선택에만.
///  - The No Neon Analytics — 차트는 green/red/blue/yellow/orange 5색 기본.

// ── 간격 스케일 (design-tokens: spacing xs4 sm8 md16 lg24 xl32) ──────────────
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

// ── 반경 스케일 (radius base 8 / md 6 / sm 4 / sheet 16) ─────────────────────
class AppRadius {
  AppRadius._();
  static const double sm = 4;
  static const double button = 6;
  static const double card = 10; // lg(8)보다 살짝 부드럽게 — 밀도 높은 화면의 시각적 안정
  static const double input = 8;
  static const double sheet = 16;
  static const double pill = 999;
}

/// 상태·차트 색상 — Material `ColorScheme`가 담지 못하는 도메인 토큰을
/// ThemeExtension으로 주입. `context.status` 로 접근.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  final Color pass, passContainer, onPassContainer;
  final Color fail, failContainer, onFailContainer;
  final Color warning, warningContainer, onWarningContainer;
  final Color process, processContainer, onProcessContainer;
  final Color info, infoContainer, onInfoContainer;
  final Color neutral, neutralContainer, onNeutralContainer;

  /// 차트 5색 시리즈 (green/red/blue/yellow/orange).
  final List<Color> chart;

  const StatusColors({
    required this.pass,
    required this.passContainer,
    required this.onPassContainer,
    required this.fail,
    required this.failContainer,
    required this.onFailContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.process,
    required this.processContainer,
    required this.onProcessContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.onNeutralContainer,
    required this.chart,
  });

  static const light = StatusColors(
    pass: Color(0xFF16A34A),
    passContainer: Color(0xFFDCFCE7),
    onPassContainer: Color(0xFF166534),
    fail: Color(0xFFDC2626),
    failContainer: Color(0xFFFEE2E2),
    onFailContainer: Color(0xFF991B1B),
    warning: Color(0xFFD97706),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    process: Color(0xFFEA580C),
    processContainer: Color(0xFFFFEDD5),
    onProcessContainer: Color(0xFF9A3412),
    info: Color(0xFF2563EB),
    infoContainer: Color(0xFFDBEAFE),
    onInfoContainer: Color(0xFF1E3A8A),
    neutral: Color(0xFF475569),
    neutralContainer: Color(0xFFF1F5F9),
    onNeutralContainer: Color(0xFF334155),
    chart: [
      Color(0xFF16A34A), // 1 green — 합격/성공
      Color(0xFFEF4444), // 2 red — 불량
      Color(0xFF2563EB), // 3 blue — 검사 건수/기준선
      Color(0xFFFACC15), // 4 yellow — 경고
      Color(0xFFFB923C), // 5 orange — 공정 이슈
    ],
  );

  static const dark = StatusColors(
    pass: Color(0xFF4ADE80),
    passContainer: Color(0xFF14532D),
    onPassContainer: Color(0xFFBBF7D0),
    fail: Color(0xFFF87171),
    failContainer: Color(0xFF7F1D1D),
    onFailContainer: Color(0xFFFECACA),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF78350F),
    onWarningContainer: Color(0xFFFDE68A),
    process: Color(0xFFFB923C),
    processContainer: Color(0xFF7C2D12),
    onProcessContainer: Color(0xFFFED7AA),
    info: Color(0xFF60A5FA),
    infoContainer: Color(0xFF1E3A8A),
    onInfoContainer: Color(0xFFBFDBFE),
    neutral: Color(0xFF94A3B8),
    neutralContainer: Color(0xFF1E293B),
    onNeutralContainer: Color(0xFFCBD5E1),
    chart: [
      Color(0xFF4ADE80),
      Color(0xFFF87171),
      Color(0xFF60A5FA),
      Color(0xFFFACC15),
      Color(0xFFFDBA74),
    ],
  );

  @override
  StatusColors copyWith({
    Color? pass,
    Color? passContainer,
    Color? onPassContainer,
    Color? fail,
    Color? failContainer,
    Color? onFailContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? process,
    Color? processContainer,
    Color? onProcessContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? onNeutralContainer,
    List<Color>? chart,
  }) {
    return StatusColors(
      pass: pass ?? this.pass,
      passContainer: passContainer ?? this.passContainer,
      onPassContainer: onPassContainer ?? this.onPassContainer,
      fail: fail ?? this.fail,
      failContainer: failContainer ?? this.failContainer,
      onFailContainer: onFailContainer ?? this.onFailContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      process: process ?? this.process,
      processContainer: processContainer ?? this.processContainer,
      onProcessContainer: onProcessContainer ?? this.onProcessContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
      chart: chart ?? this.chart,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      pass: Color.lerp(pass, other.pass, t)!,
      passContainer: Color.lerp(passContainer, other.passContainer, t)!,
      onPassContainer: Color.lerp(onPassContainer, other.onPassContainer, t)!,
      fail: Color.lerp(fail, other.fail, t)!,
      failContainer: Color.lerp(failContainer, other.failContainer, t)!,
      onFailContainer: Color.lerp(onFailContainer, other.onFailContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      process: Color.lerp(process, other.process, t)!,
      processContainer: Color.lerp(processContainer, other.processContainer, t)!,
      onProcessContainer:
          Color.lerp(onProcessContainer, other.onProcessContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      onNeutralContainer:
          Color.lerp(onNeutralContainer, other.onNeutralContainer, t)!,
      chart: [
        for (var i = 0; i < chart.length; i++)
          Color.lerp(chart[i], other.chart[i], t)!,
      ],
    );
  }
}

/// `context.status` — StatusColors 접근 단축.
extension StatusColorsX on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final status = isDark ? StatusColors.dark : StatusColors.light;

    // ── ColorScheme (design-tokens color.light / color.dark) ──────────────
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFF6366F1), // operational-blue-dark
            onPrimary: Colors.white,
            primaryContainer: Color(0xFF312E81),
            onPrimaryContainer: Color(0xFFE0E7FF),
            secondary: Color(0xFFEC4899), // analytical-magenta
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFF831843),
            onSecondaryContainer: Color(0xFFFBCFE8),
            surface: Color(0xFF111827), // dark-card
            onSurface: Color(0xFFF8FAFC),
            surfaceContainerLowest: Color(0xFF090A0B),
            surfaceContainerLow: Color(0xFF0F1623),
            surfaceContainer: Color(0xFF141C2B),
            surfaceContainerHigh: Color(0xFF1B2333),
            surfaceContainerHighest: Color(0xFF222C3D),
            onSurfaceVariant: Color(0xFF94A3B8), // muted-foreground
            outline: Color(0xFF334155),
            outlineVariant: Color(0xFF1E293B),
            error: Color(0xFFF87171),
            onError: Color(0xFF450A0A),
            errorContainer: Color(0xFF7F1D1D),
            onErrorContainer: Color(0xFFFECACA),
          )
        : const ColorScheme.light(
            primary: Color(0xFF2563EB), // operational-blue
            onPrimary: Colors.white,
            primaryContainer: Color(0xFFDBEAFE),
            onPrimaryContainer: Color(0xFF1E3A8A),
            secondary: Color(0xFFDB2777), // analytical-magenta (600, 텍스트 대비)
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFFCE7F3),
            onSecondaryContainer: Color(0xFF9D174D),
            surface: Colors.white, // card
            onSurface: Color(0xFF020817), // ink-slate
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFF8FAFC),
            surfaceContainer: Color(0xFFF1F5F9), // surface-slate
            surfaceContainerHigh: Color(0xFFE9EEF5),
            surfaceContainerHighest: Color(0xFFE2E8F0),
            onSurfaceVariant: Color(0xFF64748B), // muted-slate
            outline: Color(0xFFCBD5E1),
            outlineVariant: Color(0xFFE2E8F0), // border-slate
            error: Color(0xFFDC2626),
            onError: Colors.white,
            errorContainer: Color(0xFFFEE2E2),
            onErrorContainer: Color(0xFF991B1B),
          );

    final scaffoldBg =
        isDark ? const Color(0xFF090A0B) : const Color(0xFFF1F5F9);
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    final textTheme = _textTheme(ink, muted);

    final cardBorder = BorderSide(color: scheme.outlineVariant, width: 1);
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: cardBorder,
    );

    OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      // 장갑 착용 조작 고려 — 넉넉한 터치 타깃
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: [status],

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: AppSpacing.lg,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerLow : Colors.white,
        // iOS 확대 방지(16px)와 동일 취지 — 입력 폰트 하한 유지
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 14),
        border: inputBorder(scheme.outlineVariant),
        enabledBorder: inputBorder(scheme.outlineVariant),
        focusedBorder: inputBorder(scheme.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
        labelStyle: textTheme.bodyMedium?.copyWith(color: muted),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
            color: scheme.primary, fontWeight: FontWeight.w600),
        hintStyle: textTheme.bodyMedium?.copyWith(color: muted),
        helperStyle: textTheme.labelMedium?.copyWith(color: muted),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.onPrimaryContainer : muted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: muted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: muted),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearMinHeight: 3,
        color: scheme.primary,
      ),
    );
  }

  /// 타이포 스케일 (design-tokens typography.scale, Inter 지향).
  /// Inter 폰트는 번들하지 않고 플랫폼 기본 폰트에 스케일·트래킹만 적용
  /// (오프라인 현장 앱 — 폰트 자산·네트워크 의존 최소화).
  static TextTheme _textTheme(Color ink, Color muted) {
    TextStyle s(double size, FontWeight w, {double tracking = 0, double h = 1.3}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          letterSpacing: tracking,
          height: h,
          color: ink,
        );

    return TextTheme(
      displayLarge: s(34, FontWeight.w700, tracking: -0.5, h: 1.15),
      displayMedium: s(30, FontWeight.w700, tracking: -0.5, h: 1.15), // 핵심 KPI 숫자
      displaySmall: s(26, FontWeight.w700, tracking: -0.4, h: 1.2),
      headlineMedium: s(24, FontWeight.w600, tracking: -0.3, h: 1.2), // 섹션 헤더
      headlineSmall: s(20, FontWeight.w600, tracking: -0.2, h: 1.25),
      titleLarge: s(18, FontWeight.w600, tracking: -0.2),
      titleMedium: s(16, FontWeight.w600, tracking: -0.1), // 카드/섹션 제목
      titleSmall: s(14, FontWeight.w600),
      bodyLarge: s(16, FontWeight.w400, h: 1.5),
      bodyMedium: s(14, FontWeight.w400, h: 1.5), // 본문/테이블
      bodySmall: s(13, FontWeight.w400, h: 1.45).copyWith(color: muted),
      labelLarge: s(14, FontWeight.w600, tracking: 0.1), // 버튼
      labelMedium: s(12, FontWeight.w500, tracking: 0.2), // badge/caption
      labelSmall: s(11, FontWeight.w500, tracking: 0.3),
    );
  }
}
