import 'package:flutter/material.dart';

import '../core/ict_time.dart';
import '../core/strings.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../services/master_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'lot_detail_screen.dart';

/// LOT 이력 조회 — LOT번호 검색 / Model별 / NG만 필터 (스펙 확정 조회 기준).
class HistoryScreen extends StatefulWidget {
  final ApiClient api;
  final MasterCache masters;

  const HistoryScreen({super.key, required this.api, required this.masters});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _lotCtrl = TextEditingController();
  String? _model;
  bool _ngOnly = false;
  String _from = IctTime.workFirstOfMonth();
  String _to = IctTime.workDate();

  bool _loading = false;
  String? _error;
  List<RemoteRecord> _records = const [];
  bool _searched = false;

  @override
  void dispose() {
    _lotCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'dateFrom': _from,
        'dateTo': _to,
        if (_lotCtrl.text.trim().isNotEmpty) 'lot': _lotCtrl.text.trim(),
        if (_model != null && _model!.isNotEmpty) 'model': _model,
        if (_ngOnly) 'ngOnly': '1',
      };
      final data = await widget.api.call('list', payload);
      final list = (data['records'] as List)
          .map((e) => RemoteRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) =>
            ('${b.date} ${b.time}').compareTo('${a.date} ${a.time}'));
      setState(() => _records = list);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = S.t(context, 'networkError'));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
        });
      }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = widget.masters.cached.models;
    return Column(
      children: [
        // ── 필터 패널 ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: AppPanel(
            padding: const EdgeInsets.all(AppSpacing.sm + 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lotCtrl,
                        decoration: InputDecoration(
                          labelText: S.t(context, 'lot'),
                          prefixIcon: const Icon(Icons.numbers, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _model,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: S.t(context, 'model'),
                        ),
                        items: [
                          DropdownMenuItem(value: '', child: Text('—')),
                          for (final m in models)
                            DropdownMenuItem(value: m, child: Text(m)),
                        ],
                        onChanged: (v) => setState(() => _model = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                        child: _dateButton(context, _from, () => _pickDate(true))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Icon(Icons.arrow_forward, size: 16),
                    ),
                    Expanded(
                        child: _dateButton(context, _to, () => _pickDate(false))),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    FilterChip(
                      label: Text(S.t(context, 'ngOnly')),
                      avatar: Icon(Icons.cancel_outlined,
                          size: 16,
                          color: _ngOnly
                              ? context.status.onFailContainer
                              : context.scheme.onSurfaceVariant),
                      selected: _ngOnly,
                      selectedColor: context.status.failContainer,
                      onSelected: (v) => setState(() => _ngOnly = v),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(S.t(context, 'search')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _errorBanner(context, _error!),
          ),
        Expanded(
          child: _records.isEmpty && !_loading
              ? EmptyState(
                  message: _searched
                      ? S.t(context, 'noData')
                      : S.t(context, 'search'),
                  icon: Icons.manage_search_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                  itemCount: _records.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _recordTile(context, _records[i]),
                ),
        ),
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

  Widget _recordTile(BuildContext context, RemoteRecord r) {
    final ng = r.verdict == 'NG';
    final scheme = context.scheme;
    final kind = r.voided
        ? StatusKind.neutral
        : (ng ? StatusKind.fail : StatusKind.pass);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => LotDetailScreen(api: widget.api, record: r),
            ),
          );
          if (changed == true) _search();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
          child: Row(
            children: [
              // 판정 배지 (색 + 텍스트)
              StatusChip(
                kind: kind,
                label: r.voided ? S.t(context, 'voided') : r.verdict,
                solid: !r.voided,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('LOT ${r.lot}  ·  ${r.model}',
                              style: Theme.of(context).textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (r.rework) ...[
                          const SizedBox(width: AppSpacing.sm),
                          StatusChip(
                            kind: StatusKind.process,
                            label: S.t(context, 'rework'),
                            icon: Icons.build_rounded,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${r.date} ${r.time}  ·  ${r.ca}  ·  ${r.inspector}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // 사진 상태 (대기 개수 or 완료)
              r.anyPhotoPending
                  ? Badge(
                      label: Text('${r.pendingPhotoCount}'),
                      backgroundColor: context.status.process,
                      child: Icon(Icons.cloud_upload_outlined,
                          color: context.status.process),
                    )
                  : Icon(Icons.photo_outlined,
                      color: scheme.onSurfaceVariant),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    final st = context.status;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
}
