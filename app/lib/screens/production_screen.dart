import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/ict_time.dart';
import '../core/strings.dart';
import '../models/production.dart';
import '../services/api_client.dart';
import '../services/master_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 생산 탭 — 생산 투입 등록(LOT 자동채번) + Rework 재투입 대기 목록.
///
/// 생산 투입/Rework 재투입은 온라인 작업(서버 LOT 채번·목록 연동이 필요).
/// 검사 저장(무손실 오프라인 큐)과 달리 네트워크가 필요하며, 실패 시 재시도 안내.
class ProductionScreen extends StatefulWidget {
  final ApiClient api;
  final MasterCache masters;

  const ProductionScreen({super.key, required this.api, required this.masters});

  @override
  State<ProductionScreen> createState() => ProductionScreenState();
}

class ProductionScreenState extends State<ProductionScreen> {
  static const _uuid = Uuid();

  final _modelCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  bool _saving = false;

  bool _loadingRework = false;
  List<ProductionRecord> _reworkWaiting = const [];

  @override
  void initState() {
    super.initState();
    _modelCtrl.text = AppSettings.lastModel;
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  /// 탭 진입 시 HomeShell이 호출 — Rework 대기 목록 갱신.
  Future<void> refresh() async {
    setState(() => _loadingRework = true);
    try {
      final data = await widget.api.call('productionList', {
        'dateFrom': IctTime.workFirstOfMonth(),
        'dateTo': IctTime.workDate(),
      });
      final list = (data['records'] as List)
          .map((e) =>
              ProductionRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((r) => r.awaitingReworkInput)
          .toList();
      if (mounted) setState(() => _reworkWaiting = list);
    } catch (_) {
      // 오프라인 등 — 조용히 무시(재시도 가능)
    } finally {
      if (mounted) setState(() => _loadingRework = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.masters.cached;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          // ── 생산 투입 등록 ─────────────────────────────────────────────
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(S.t(context, 'productionInput')),
                const SizedBox(height: AppSpacing.md),
                _readonlyRow(
                  context,
                  icon: Icons.schedule,
                  label: '${S.t(context, 'date')} · ${S.t(context, 'time')}',
                  value: '${IctTime.workDate()}   ${IctTime.nowTime()}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: context.scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(S.t(context, 'lotAuto'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _modelField(context, m),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'qty'),
                    prefixIcon: const Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_circle_outline),
                  label: Text(S.t(context, 'produce')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Rework 재투입 대기 ─────────────────────────────────────────
          SectionHeader(
            S.t(context, 'reworkWaiting'),
            trailing: _loadingRework
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : (_reworkWaiting.isNotEmpty
                    ? StatusChip(
                        kind: StatusKind.process,
                        label: '${_reworkWaiting.length}',
                        icon: Icons.build_rounded,
                        dense: true,
                      )
                    : null),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          if (_reworkWaiting.isEmpty && !_loadingRework)
            EmptyState(
                message: S.t(context, 'noData'),
                icon: Icons.build_circle_outlined)
          else
            for (final r in _reworkWaiting) ...[
              _reworkTile(context, r),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }

  /// 읽기 전용 컨텍스트 요약 행 (입력 전 컨텍스트 먼저 — 디자인 킷 폼 규칙).
  Widget _readonlyRow(BuildContext context,
      {required IconData icon, required String label, required String value}) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm + 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _modelField(BuildContext context, Masters m) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _modelCtrl.text),
      optionsBuilder: (v) => v.text.isEmpty
          ? m.models
          : m.models
              .where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (v) => _modelCtrl.text = v,
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
        controller: ctrl,
        focusNode: focus,
        onChanged: (v) => _modelCtrl.text = v,
        decoration: InputDecoration(
          labelText: S.t(context, 'model'),
          prefixIcon: const Icon(Icons.category_outlined),
        ),
      ),
    );
  }

  Widget _reworkTile(BuildContext context, ProductionRecord r) {
    final scheme = context.scheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm + 4, AppSpacing.md, AppSpacing.sm + 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.status.processContainer,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Icon(Icons.build_rounded,
                  color: context.status.onProcessContainer, size: 20),
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('R${r.lot}  ·  ${r.model}',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text('${S.t(context, 'qty')}: ${r.qty}  ·  ${r.intime}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: () => _reworkInput(r),
              child: Text(S.t(context, 'reworkInputBtn')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_modelCtrl.text.trim().isEmpty || _qtyCtrl.text.trim().isEmpty) {
      messenger.showSnackBar(statusSnackBar(
          context, S.t(context, 'fieldRequired'), StatusKind.warning));
      return;
    }
    final qty = num.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      messenger.showSnackBar(statusSnackBar(
          context, S.t(context, 'qtyInvalid'), StatusKind.warning));
      return;
    }
    setState(() => _saving = true);
    final networkError = S.t(context, 'networkError');
    final producedLabel = S.t(context, 'produced');
    final passColor = context.status.pass;
    final failColor = context.status.fail;
    try {
      final data = await widget.api.call('produce', {
        'reqId': _uuid.v4(),
        'date': IctTime.workDate(),
        'time': IctTime.nowTime(),
        'model': _modelCtrl.text.trim(),
        'qty': qty,
      });
      AppSettings.lastModel = _modelCtrl.text.trim();
      final lot = '${data['lot']}';
      messenger.showSnackBar(coloredSnackBar(
          '$producedLabel: $lot', passColor, Icons.check_circle_rounded));
      setState(() => _qtyCtrl.clear());
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkError, failColor, Icons.error_outline));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reworkInput(ProductionRecord r) async {
    final messenger = ScaffoldMessenger.of(context);
    final networkError = S.t(context, 'networkError');
    final doneMsg = S.t(context, 'reworkDone');
    final warnMsg = S.t(context, 'reworkQtyWarn');
    final passColor = context.status.pass;
    final warnColor = context.status.warning;
    final failColor = context.status.fail;
    final qty = await _promptQty(r);
    if (qty == null) return;
    try {
      final data = await widget.api.call('reworkInput', {
        'lot': r.lot,
        'date': IctTime.workDate(),
        'time': IctTime.nowTime(),
        'qty': qty,
      });
      final warn = data['warn'];
      messenger.showSnackBar(coloredSnackBar(
        warn == null ? doneMsg : warnMsg,
        warn == null ? passColor : warnColor,
        warn == null ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
      ));
      refresh();
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkError, failColor, Icons.error_outline));
    }
  }

  Future<num?> _promptQty(ProductionRecord r) async {
    final ctrl = TextEditingController();
    return showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('R${r.lot} · ${S.t(ctx, 'reworkInputBtn')}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.t(ctx, 'reworkQty'),
            helperText: '${S.t(ctx, 'qty')}: ${r.qty}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              final q = num.tryParse(ctrl.text.trim());
              if (q != null && q > 0) Navigator.pop(ctx, q);
            },
            child: Text(S.t(ctx, 'confirm')),
          ),
        ],
      ),
    );
  }
}
