import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/ict_time.dart';
import '../core/strings.dart';
import '../models/inspection.dart';
import '../models/production.dart';
import '../services/api_client.dart';
import '../services/master_cache.dart';
import '../services/photo_service.dart';
import '../services/sync_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 검사 입력 화면 (생산 통합 재설계).
///
/// LOT을 자동채번하지 않고, 미검사 생산LOT을 드롭다운에서 선택한다.
/// MODEL은 선택한 생산LOT에서 자동채움(수정불가). Bar·CA·검사자·Rack1~5·사진5장은 입력.
/// 저장은 무손실 로컬 큐(오프라인 안전). 미검사 목록은 온라인 조회.
class InspectionFormScreen extends StatefulWidget {
  final ApiClient api;
  final SyncQueue queue;
  final MasterCache masters;
  final PhotoService photoService;

  const InspectionFormScreen({
    super.key,
    required this.api,
    required this.queue,
    required this.masters,
    required this.photoService,
  });

  @override
  State<InspectionFormScreen> createState() => InspectionFormScreenState();
}

class InspectionFormScreenState extends State<InspectionFormScreen> {
  static const _uuid = Uuid();

  final _barCtrl = TextEditingController();

  String _ca = '';
  String _inspector = '';
  final List<String?> _racks = List.filled(5, null);
  final List<CapturedPhoto?> _rackPhotos = List.filled(5, null);
  bool _saving = false;

  List<UninspectedLot> _uninspected = const [];
  UninspectedLot? _selectedLot;
  bool _loadingLots = false;

  @override
  void initState() {
    super.initState();
    _ca = AppSettings.ca;
    _inspector = AppSettings.inspector;
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshLots());
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  /// 탭 진입 시 HomeShell이 호출 — 미검사 생산LOT 목록 갱신.
  Future<void> refreshLots() async {
    setState(() => _loadingLots = true);
    try {
      final data = await widget.api.call('listUninspected', {});
      final list = (data['records'] as List)
          .map((e) =>
              UninspectedLot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) {
        setState(() {
          _uninspected = list;
          // 선택 LOT이 목록에서 사라졌으면 해제
          if (_selectedLot != null &&
              !list.any((l) => l.lot == _selectedLot!.lot)) {
            _selectedLot = null;
          }
        });
      }
    } catch (_) {
      // 오프라인 — 조용히 무시
    } finally {
      if (mounted) setState(() => _loadingLots = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.masters.cached;
    // 진행 상태: 판정/사진 완료 개수 (스캔 순서를 돕는 진행 표시)
    final judged = _racks.where((r) => r != null).length;
    final photographed = _rackPhotos.where((p) => p != null).length;

    return RefreshIndicator(
      onRefresh: refreshLots,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          // ── LOT 선택 + 컨텍스트 ─────────────────────────────────────────
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _readonlyRow(
                  context,
                  icon: Icons.schedule,
                  label: '${S.t(context, 'date')} · ${S.t(context, 'time')}',
                  value: '${IctTime.workDate()}   ${IctTime.nowTime()}',
                ),
                const SizedBox(height: AppSpacing.md),
                _lotSelector(context),
                const SizedBox(height: AppSpacing.md),
                _modelDisplay(context),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _caField(context, m)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _inspectorField(context, m)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _barCtrl,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'bar'),
                    prefixIcon: const Icon(Icons.shopping_cart_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── 판정 · 사진 (Rack 1~5) ──────────────────────────────────────
          SectionHeader(
            '${S.t(context, 'result')} · ${S.t(context, 'photo')}',
            trailing: _progressChip(context, judged, photographed),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          AppPanel(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Column(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _rackRow(context, i),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_alt_rounded),
            label: Text(S.t(context, 'save')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressChip(BuildContext context, int judged, int photographed) {
    final done = judged == 5 && photographed == 5;
    return StatusChip(
      kind: done ? StatusKind.pass : StatusKind.neutral,
      label: '$judged·$photographed/5',
      icon: done ? Icons.check_circle_rounded : Icons.checklist_rounded,
      dense: true,
    );
  }

  Widget _readonlyRow(BuildContext context,
      {required IconData icon, required String label, required String value}) {
    final scheme = context.scheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
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

  Widget _caField(BuildContext context, Masters m) {
    final cas = m.cas.isEmpty ? ['CA1', 'CA2', 'CA3'] : m.cas;
    return DropdownButtonFormField<String>(
      initialValue: cas.contains(_ca) ? _ca : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: S.t(context, 'ca'),
        prefixIcon: const Icon(Icons.groups_outlined),
      ),
      items: [for (final c in cas) DropdownMenuItem(value: c, child: Text(c))],
      onChanged: (v) {
        setState(() => _ca = v ?? '');
        AppSettings.ca = _ca;
      },
    );
  }

  Widget _inspectorField(BuildContext context, Masters m) {
    return DropdownButtonFormField<String>(
      initialValue: m.inspectors.contains(_inspector) ? _inspector : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: S.t(context, 'inspector'),
        prefixIcon: const Icon(Icons.badge_outlined),
      ),
      items: [
        for (final p in m.inspectors)
          DropdownMenuItem(value: p, child: Text(p))
      ],
      onChanged: (v) {
        setState(() => _inspector = v ?? '');
        AppSettings.inspector = _inspector;
      },
    );
  }

  /// 미검사 생산LOT 드롭다운 (최신순, MODEL·수량 표시). 새로고침 버튼 포함.
  Widget _lotSelector(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _selectedLot?.lot,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: S.t(context, 'selectLot'),
              prefixIcon: const Icon(Icons.inventory_2_outlined),
            ),
            items: [
              for (final l in _uninspected)
                DropdownMenuItem(
                    value: l.lot,
                    child:
                        Text(l.displayLabel, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(
                () => _selectedLot = _uninspected.firstWhere((l) => l.lot == v)),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
          onPressed: _loadingLots ? null : refreshLots,
          icon: _loadingLots
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          tooltip: S.t(context, 'refreshLots'),
        ),
      ],
    );
  }

  /// 선택한 LOT의 MODEL 자동표시 (수정 불가).
  Widget _modelDisplay(BuildContext context) {
    final scheme = context.scheme;
    final has = _selectedLot != null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: S.t(context, 'model'),
        prefixIcon: const Icon(Icons.category_outlined),
        enabled: has,
      ),
      child: Text(
        _selectedLot?.model ?? '—',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: has ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _rackRow(BuildContext context, int i) {
    final value = _racks[i];
    final photo = _rackPhotos[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text('Rack ${i + 1}',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: _judgeButton(
                      context,
                      label: 'OK',
                      icon: Icons.check_rounded,
                      selected: value == 'OK',
                      kind: StatusKind.pass,
                      onTap: () => setState(() => _racks[i] = 'OK'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm - 2),
                  Expanded(
                    child: _judgeButton(
                      context,
                      label: 'NG',
                      icon: Icons.close_rounded,
                      selected: value == 'NG',
                      kind: StatusKind.fail,
                      onTap: () => setState(() => _racks[i] = 'NG'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          _rackPhotoButton(context, i, photo),
        ],
      ),
    );
  }

  Widget _judgeButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required StatusKind kind,
    required VoidCallback onTap,
  }) {
    final st = context.status;
    final color = kind == StatusKind.pass ? st.pass : st.fail;
    return Material(
      color: selected ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
                color: color, width: selected ? 0 : 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected ? Colors.white : color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rackPhotoButton(BuildContext context, int i, CapturedPhoto? photo) {
    final st = context.status;
    final captured = photo != null;
    final borderColor = captured ? st.pass : st.warning;
    return GestureDetector(
      onTap: () => _takeRackPhoto(i),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: captured ? null : st.warningContainer,
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: captured
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                    child: Image.memory(photo.jpegBytes,
                        width: 44, height: 44, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                          color: st.pass, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(1),
                      child: const Icon(Icons.check,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ],
              )
            : Icon(Icons.camera_alt_outlined,
                color: st.onWarningContainer, size: 22),
      ),
    );
  }

  Future<void> _takeRackPhoto(int i) async {
    final photo = await widget.photoService.captureAndCompress(i + 1);
    if (photo != null) setState(() => _rackPhotos[i] = photo);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final warnColor = context.status.warning;
    String? error;
    if (_selectedLot == null) {
      error = S.t(context, 'selectLotFirst');
    } else if (_inspector.isEmpty) {
      error = S.t(context, 'selectInspector');
    } else if (_ca.isEmpty ||
        _barCtrl.text.trim().isEmpty ||
        _racks.any((r) => r == null)) {
      error = S.t(context, 'fieldRequired');
    } else if (_rackPhotos.any((p) => p == null)) {
      error = S.t(context, 'photoPerRackRequired');
    }
    if (error != null) {
      messenger.showSnackBar(
          coloredSnackBar(error, warnColor, Icons.warning_amber_rounded));
      return;
    }

    setState(() => _saving = true);
    final savedOk = S.t(context, 'savedOk');
    final savedNg = S.t(context, 'savedNg');
    final passColor = context.status.pass;
    final failColor = context.status.fail;
    final lot = _selectedLot!;

    final insp = Inspection(
      uuid: _uuid.v4(),
      date: IctTime.workDate(),
      ca: _ca,
      inspector: _inspector,
      lot: lot.lot,
      time: IctTime.nowTime(),
      bar: _barCtrl.text.trim(),
      model: lot.model,
      racks: _racks.map((r) => r!).toList(),
    );

    await widget.queue.enqueue(insp, _rackPhotos.map((p) => p!).toList());

    final isNg = insp.verdict == 'NG';
    messenger.showSnackBar(coloredSnackBar(
      isNg ? savedNg : savedOk,
      isNg ? failColor : passColor,
      isNg ? Icons.cancel_rounded : Icons.check_circle_rounded,
    ));

    setState(() {
      // 방금 검사한 LOT은 목록에서 제거(낙관적) — 다음 검사 대상으로 이동
      _uninspected = _uninspected.where((l) => l.lot != lot.lot).toList();
      _selectedLot = null;
      _barCtrl.clear();
      for (var i = 0; i < 5; i++) {
        _racks[i] = null;
        _rackPhotos[i] = null;
      }
      _saving = false;
    });
  }
}
