import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/ict_time.dart';
import '../core/strings.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../services/sync_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 대시보드 — 검사자용 요약(오늘 내 검사/NG) + 관리자용 모니터링
/// (기간·Model별 NG율, pending 사진 카운트). 스펙 R4 "둘 다 필요" 반영.
class DashboardScreen extends StatefulWidget {
  final ApiClient api;
  final SyncQueue queue;

  const DashboardScreen({super.key, required this.api, required this.queue});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  /// 탭 진입 시 HomeShell이 호출 — 대시보드는 열 때마다 최신 데이터로 갱신한다
  /// (앱 시작 시 API 미설정 상태에서 실행됐던 초기 조회 오류를 덮어씀).
  void refresh() => _refresh();

  String _from = IctTime.workFirstOfMonth();
  String _to = IctTime.workDate();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _prodStats;
  int _myToday = 0;
  int _myTodayNg = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await widget.api
          .call('stats', {'dateFrom': _from, 'dateTo': _to});
      final prodStats = await widget.api
          .call('productionStats', {'dateFrom': _from, 'dateTo': _to});

      // 검사자 개인 요약: 오늘 기록을 조회해 본인 것만 집계
      final today = IctTime.workDate();
      final myList = await widget.api
          .call('list', {'dateFrom': today, 'dateTo': today});
      final inspector = AppSettings.inspector;
      var my = 0, myNg = 0;
      for (final e in myList['records'] as List) {
        final r = RemoteRecord.fromJson(Map<String, dynamic>.from(e as Map));
        if (r.inspector == inspector) {
          my++;
          if (r.verdict == 'NG') myNg++;
        }
      }
      setState(() {
        _stats = stats;
        _prodStats = prodStats;
        _myToday = my;
        _myTodayNg = myNg;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = S.t(context, 'networkError'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = DateTime.tryParse(isFrom ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = IctTime.dateStr(picked);
        } else {
          _to = IctTime.dateStr(picked);
        }
      });
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final byModel = (s?['byModel'] as Map?)?.cast<String, dynamic>() ?? {};
    final ngRate = (s?['ngRate'] as num?)?.toDouble() ?? 0;
    final total = s?['total'];
    final ng = s?['ng'];
    final queuedToday =
        widget.queue.pendingRecordsForInspectorToday(AppSettings.inspector);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          // ── 1. 생산 지표 (한눈에 보는 생산 현황 — 최상단 헤드라인) ─────────
          SectionHeader(S.t(context, 'prodStatsTitle')),
          const SizedBox(height: AppSpacing.sm + 2),
          _prodKpis(context),
          const Divider(),

          // ── 2. 기간 설정 (아래 모든 지표에 적용되는 조회 기간) ────────────
          SectionHeader(S.t(context, 'period')),
          const SizedBox(height: AppSpacing.sm),
          _periodFilter(context),
          if (_loading) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _errorBanner(context, _error!),
          ],
          const Divider(),

          // ── 3. 품질 모니터링 (전체/NG/NG율 + 전송 대기 사진) ──────────────
          SectionHeader(S.t(context, 'monitoring')),
          const SizedBox(height: AppSpacing.sm + 2),
          _kpiRow([
            KpiCard(
              label: S.t(context, 'total'),
              value: '${total ?? '—'}',
              icon: Icons.inventory_2_outlined,
              tone: StatusKind.neutral,
            ),
            KpiCard(
              label: S.t(context, 'ngCount'),
              value: '${ng ?? '—'}',
              icon: Icons.cancel_outlined,
              tone: (ng is num && ng > 0) ? StatusKind.fail : StatusKind.neutral,
              emphasizeValue: true,
            ),
            KpiCard(
              label: S.t(context, 'ngRate'),
              value: s == null ? '—' : '${(ngRate * 100).toStringAsFixed(1)}%',
              icon: Icons.percent_rounded,
              tone: ngRate > 0 ? StatusKind.warning : StatusKind.neutral,
              emphasizeValue: true,
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          // pending 사진 가시성 (Critic M2 — 사진 무손실 모니터링)
          KpiCard(
            label: S.t(context, 'pendingPhotos'),
            value:
                '${(s?['pendingPhotos'] ?? 0)}${widget.queue.pendingPhotos > 0 ? ' +${widget.queue.pendingPhotos}' : ''}',
            icon: Icons.cloud_upload_outlined,
            tone: ((s?['pendingPhotos'] as num?) ?? 0) + widget.queue.pendingPhotos > 0
                ? StatusKind.process
                : StatusKind.neutral,
          ),
          const Divider(),

          // ── 4. Model별 현황 ──────────────────────────────────────────────
          SectionHeader(S.t(context, 'byModel')),
          const SizedBox(height: AppSpacing.sm + 2),
          if (byModel.isEmpty)
            EmptyState(
                message: S.t(context, 'noData'),
                icon: Icons.bar_chart_outlined)
          else
            MetricTable(
              columns: [
                S.t(context, 'model'),
                S.t(context, 'total'),
                'NG',
                S.t(context, 'ngRate'),
              ],
              flex: const [3, 2, 2, 2],
              rows: [
                for (final entry in byModel.entries)
                  _modelRow(context, entry.key, entry.value as Map),
              ],
            ),
          const Divider(),

          // ── 5. 기간별 추이 (일별 생산·NG) ────────────────────────────────
          _prodTrend(context),
          const Divider(),

          // ── 6. 금일 검사 (검사자 개인 요약 — 최하단) ──────────────────────
          SectionHeader(S.t(context, 'myToday'), caption: IctTime.workDate()),
          const SizedBox(height: AppSpacing.sm + 2),
          _kpiRow([
            KpiCard(
              label: S.t(context, 'myToday'),
              value: '${_myToday + queuedToday}',
              icon: Icons.fact_check_outlined,
              caption: queuedToday > 0
                  ? '+$queuedToday ${S.t(context, 'pendingRecords')}'
                  : null,
              tone: StatusKind.info,
            ),
            KpiCard(
              label: S.t(context, 'myNg'),
              value: '$_myTodayNg',
              icon: Icons.report_problem_outlined,
              tone: _myTodayNg > 0 ? StatusKind.fail : StatusKind.neutral,
              emphasizeValue: true,
            ),
          ]),
        ],
      ),
    );
  }

  /// KPI 카드 행 — 동일 높이 정렬(IntrinsicHeight) + 토큰 간격.
  Widget _kpiRow(List<Widget> cards) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  Widget _periodFilter(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _dateButton(context, _from, () => _pickDate(true))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Icon(Icons.arrow_forward, size: 16),
        ),
        Expanded(child: _dateButton(context, _to, () => _pickDate(false))),
      ],
    );
  }

  Widget _dateButton(BuildContext context, String date, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(date, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: context.scheme.onSurface,
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    final st = context.status;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: st.failContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: st.fail.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: st.onFailContainer, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: st.onFailContainer)),
          ),
        ],
      ),
    );
  }

  List<Widget> _modelRow(BuildContext context, String model, Map m) {
    final total = (m['total'] as num?)?.toDouble() ?? 0;
    final ng = (m['ng'] as num?)?.toDouble() ?? 0;
    final rate = total == 0 ? null : ng / total;
    final rateColor = rate == null
        ? null
        : (rate > 0 ? context.status.fail : context.scheme.onSurfaceVariant);
    return [
      MetricTable.cell(context, model, bold: true),
      MetricTable.cell(context, '${m['total']}', align: TextAlign.end),
      MetricTable.cell(context, '${m['ng']}',
          align: TextAlign.end,
          color: ng > 0 ? context.status.fail : null),
      MetricTable.cell(
        context,
        rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%',
        align: TextAlign.end,
        bold: true,
        color: rateColor,
      ),
    ];
  }

  /// 생산 KPI 카드: 생산건수·생산수량 / 검사율·미검사·Rework율.
  Widget _prodKpis(BuildContext context) {
    final p = _prodStats;
    String pct(String k) => p == null
        ? '—'
        : '${(((p[k] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%';
    final uninspected = p?['uninspected'];

    return Column(
      children: [
        _kpiRow([
          KpiCard(
            label: S.t(context, 'prodTotal'),
            value: '${p?['produced'] ?? '—'}',
            icon: Icons.precision_manufacturing_outlined,
            tone: StatusKind.neutral,
          ),
          KpiCard(
            label: S.t(context, 'prodQty'),
            value: '${p?['qtySum'] ?? '—'}',
            icon: Icons.layers_outlined,
            tone: StatusKind.neutral,
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _kpiRow([
          KpiCard(
            label: S.t(context, 'inspectRate'),
            value: pct('inspectRate'),
            icon: Icons.verified_outlined,
            tone: StatusKind.pass,
            emphasizeValue: true,
          ),
          KpiCard(
            label: S.t(context, 'uninspectedCnt'),
            value: '${uninspected ?? '—'}',
            icon: Icons.pending_actions_outlined,
            tone: (uninspected is num && uninspected > 0)
                ? StatusKind.warning
                : StatusKind.neutral,
            emphasizeValue: true,
          ),
          KpiCard(
            label: S.t(context, 'reworkRate'),
            value: pct('reworkRate'),
            icon: Icons.build_outlined,
            tone: StatusKind.process,
            emphasizeValue: true,
          ),
        ]),
      ],
    );
  }

  /// 기간별 추이 (일별 생산·NG) — 섹션 헤더 + 테이블.
  Widget _prodTrend(BuildContext context) {
    final byDay =
        (_prodStats?['byDay'] as Map?)?.cast<String, dynamic>() ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(S.t(context, 'prodTrend')),
        const SizedBox(height: AppSpacing.sm),
        if (byDay.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(S.t(context, 'noData'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant)),
          )
        else
          MetricTable(
            columns: [
              S.t(context, 'date'),
              S.t(context, 'prodTotal'),
              'NG',
            ],
            flex: const [2, 1, 1],
            rows: [
              for (final e in (byDay.entries.toList()
                ..sort((a, b) => b.key.compareTo(a.key))))
                [
                  MetricTable.cell(context, e.key),
                  MetricTable.cell(context, '${(e.value as Map)['produced']}',
                      align: TextAlign.end),
                  MetricTable.cell(context, '${(e.value as Map)['ng']}',
                      align: TextAlign.end,
                      color: (((e.value as Map)['ng'] as num?) ?? 0) > 0
                          ? context.status.fail
                          : null),
                ],
            ],
          ),
      ],
    );
  }
}
