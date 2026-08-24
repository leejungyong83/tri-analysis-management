import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// TRI UI 키트 — 디자인 킷 섹션 7 "컴포넌트 규칙"의 Flutter 구현.
/// KpiCard / StatusChip / SectionHeader / AppPanel / MetricTable / EmptyState.

/// 상태 종류 — "The Status Must Speak Twice"의 축.
/// 각 종류는 (색상 + 아이콘 + 텍스트)를 항상 함께 렌더한다.
enum StatusKind { pass, fail, warning, process, info, neutral }

/// 색·아이콘을 명시해 SnackBar를 만든다 (context 불필요 — async gap 이후 안전).
/// 색은 await 전에 `context.status.xxx`로 캡처해 넘긴다. 항상 아이콘+텍스트 동반.
SnackBar coloredSnackBar(String message, Color color, IconData icon) {
  return SnackBar(
    backgroundColor: color,
    content: Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

/// 동기 호출부(await 없음)용 — StatusKind로 색·아이콘을 해석해 SnackBar 생성.
SnackBar statusSnackBar(BuildContext context, String message, StatusKind kind) {
  final v = _visual(context, kind);
  return coloredSnackBar(message, v.fg, v.icon);
}

class _StatusVisual {
  final Color fg; // 강조 색 (아이콘/값)
  final Color container; // 옅은 배경
  final Color onContainer; // 배경 위 텍스트/아이콘
  final IconData icon;
  const _StatusVisual(this.fg, this.container, this.onContainer, this.icon);
}

_StatusVisual _visual(BuildContext context, StatusKind kind) {
  final s = context.status;
  switch (kind) {
    case StatusKind.pass:
      return _StatusVisual(
          s.pass, s.passContainer, s.onPassContainer, Icons.check_circle_rounded);
    case StatusKind.fail:
      return _StatusVisual(
          s.fail, s.failContainer, s.onFailContainer, Icons.cancel_rounded);
    case StatusKind.warning:
      return _StatusVisual(s.warning, s.warningContainer, s.onWarningContainer,
          Icons.warning_amber_rounded);
    case StatusKind.process:
      return _StatusVisual(s.process, s.processContainer, s.onProcessContainer,
          Icons.autorenew_rounded);
    case StatusKind.info:
      return _StatusVisual(
          s.info, s.infoContainer, s.onInfoContainer, Icons.info_rounded);
    case StatusKind.neutral:
      return _StatusVisual(s.neutral, s.neutralContainer, s.onNeutralContainer,
          Icons.circle_outlined);
  }
}

/// 상태 칩 — 색 + 아이콘 + 텍스트를 항상 함께. (색상 단독 금지)
class StatusChip extends StatelessWidget {
  final StatusKind kind;
  final String label;
  final IconData? icon;
  final bool dense;
  final bool solid; // true면 채운 배경(종합판정 등 강한 강조)

  const StatusChip({
    super.key,
    required this.kind,
    required this.label,
    this.icon,
    this.dense = false,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = _visual(context, kind);
    final bg = solid ? v.fg : v.container;
    final fg = solid ? _onSolid(context, kind) : v.onContainer;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? AppSpacing.sm : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: solid ? null : Border.all(color: v.fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? v.icon, size: dense ? 13 : 15, color: fg),
          SizedBox(width: dense ? 3 : 5),
          Text(
            label,
            style: (dense ? tt.labelSmall : tt.labelMedium)?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _onSolid(BuildContext context, StatusKind kind) => Colors.white;
}

/// KPI 카드 — label / value / icon / caption 구조 (디자인 킷 섹션 7).
/// tone이 neutral이 아니고 emphasize=true면 값에 상태색을 입힌다.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final StatusKind tone;
  final bool emphasizeValue;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone = StatusKind.neutral,
    this.emphasizeValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = context.scheme;
    final v = _visual(context, tone);

    // neutral 톤은 primary(파랑) 틴트로 브랜드 일관성 유지 — 무지개 색상 금지
    final chipBg =
        tone == StatusKind.neutral ? scheme.surfaceContainerHighest : v.container;
    final chipFg =
        tone == StatusKind.neutral ? scheme.onSurfaceVariant : v.onContainer;
    final valueColor =
        (emphasizeValue && tone != StatusKind.neutral) ? v.fg : scheme.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: tt.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Icon(icon, size: 17, color: chipFg),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: tt.headlineMedium?.copyWith(
                    color: valueColor, fontWeight: FontWeight.w700),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(caption!,
                  style: tt.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 섹션 헤더 — 제목 + (선택)설명 + (선택)우측 액션. 페이지 스캔 순서를 명확히.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.caption,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleMedium),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(caption!,
                        style: tt.bodySmall
                            ?.copyWith(color: context.scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 정보를 묶는 카드 패널 — 폼 섹션·그룹 컨테이너. (페이지 장식 배경 아님)
class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: padding, child: child));
  }
}

/// 밀도 높은 지표 테이블 — 헤더 틴트 + 행 구분선 + 라운드 컨테이너.
/// 셀은 위젯이므로 상태색·정렬을 호출부에서 제어한다.
class MetricTable extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;
  final List<int> flex; // 컬럼별 가중치 (기본 첫 컬럼 2, 나머지 1)

  const MetricTable({
    super.key,
    required this.columns,
    required this.rows,
    this.flex = const [],
  });

  static Widget cell(BuildContext context, String text,
      {bool bold = false, Color? color, TextAlign align = TextAlign.start}) {
    final tt = Theme.of(context).textTheme;
    return Text(
      text,
      textAlign: align,
      style: (bold ? tt.titleSmall : tt.bodyMedium)?.copyWith(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final weights = flex.isNotEmpty
        ? flex
        : [for (var i = 0; i < columns.length; i++) i == 0 ? 2 : 1];
    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < weights.length; i++)
        i: FlexColumnWidth(weights[i].toDouble()),
    };

    TableRow header = TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainer),
      children: [
        for (var i = 0; i < columns.length; i++)
          _pad(cell(context, columns[i],
              bold: true, align: i == 0 ? TextAlign.start : TextAlign.end)),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Table(
          columnWidths: widths,
          border: TableBorder(
            horizontalInside: BorderSide(color: scheme.outlineVariant),
          ),
          children: [
            header,
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r.isOdd
                      ? scheme.surfaceContainerLow
                      : scheme.surface,
                ),
                children: [for (final c in rows[r]) _pad(c)],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pad(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2, vertical: 10),
        child: child,
      );
}

/// 빈 상태 — 가운데 정렬 짧은 안내(장식 이미지 없음, 디자인 킷 섹션 7).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.xl),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
