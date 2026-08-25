import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/ict_time.dart';
import '../core/strings.dart';
import '../models/inspection.dart';
import '../models/production.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 전체 데이터 관리(생산/검사) — 관리자 전용. 추가·수정·삭제 모두 가능.
/// 원 설계(audit 보존, void+재입력)를 관리자 한정으로 우회 — 삭제는 되돌릴 수 없다.
/// 목록 조회는 기존 앱 토큰 경로(ApiClient), 실제 변경(추가/수정/삭제)은 로그인
/// 세션(JWT) 필요 — Supabase.instance.client.rpc(...) 직접 사용.
class AdminDataScreen extends StatefulWidget {
  final ApiClient api;
  const AdminDataScreen({super.key, required this.api});

  @override
  State<AdminDataScreen> createState() => _AdminDataScreenState();
}

class _AdminDataScreenState extends State<AdminDataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final String _from = IctTime.workFirstOfMonth();
  final String _to = IctTime.workDate();

  bool _loadingProd = false;
  List<ProductionRecord> _prod = const [];
  bool _loadingInsp = false;
  List<RemoteRecord> _insp = const [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadProd();
    _loadInsp();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadProd() async {
    setState(() => _loadingProd = true);
    try {
      final data = await widget.api
          .call('productionList', {'dateFrom': _from, 'dateTo': _to});
      final list = (data['records'] as List)
          .map((e) =>
              ProductionRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.intime.compareTo(a.intime));
      if (mounted) setState(() => _prod = list);
    } catch (_) {
      // 무시 — 화면에 빈 목록으로 표시, 재시도는 새로고침으로
    } finally {
      if (mounted) setState(() => _loadingProd = false);
    }
  }

  Future<void> _loadInsp() async {
    setState(() => _loadingInsp = true);
    try {
      final data =
          await widget.api.call('list', {'dateFrom': _from, 'dateTo': _to});
      final list = (data['records'] as List)
          .map((e) => RemoteRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => ('${b.date} ${b.time}').compareTo('${a.date} ${a.time}'));
      if (mounted) setState(() => _insp = list);
    } catch (_) {
      // 무시
    } finally {
      if (mounted) setState(() => _loadingInsp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'dataMgmt')),
        bottom: TabBar(controller: _tab, tabs: [
          Tab(text: S.t(context, 'tabProduction')),
          Tab(text: S.t(context, 'tabInspect')),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tab.index == 0) {
            _editProduction(null);
          } else {
            _editInspection(null);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(controller: _tab, children: [
        _prodList(),
        _inspList(),
      ]),
    );
  }

  // ---------------------------------------------------------------- 생산

  Widget _prodList() {
    return RefreshIndicator(
      onRefresh: _loadProd,
      child: _loadingProd && _prod.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _prod.isEmpty
              ? ListView(children: [
                  const SizedBox(height: AppSpacing.xl),
                  EmptyState(message: S.t(context, 'noData'), icon: Icons.inbox_outlined),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _prod.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final r = _prod[i];
                    return AppPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('LOT ${r.lot}  ·  ${r.model}',
                                    style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                    '${S.t(context, 'qty')}: ${r.qty}  ·  ${r.intime}  ·  ${r.status}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: context.scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editProduction(r),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: context.status.fail),
                            onPressed: () => _confirmDeleteProduction(r),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _editProduction(ProductionRecord? r) async {
    final lotCtrl = TextEditingController(text: r?.lot ?? '');
    final modelCtrl = TextEditingController(text: r?.model ?? '');
    final qtyCtrl = TextEditingController(text: r != null ? '${r.qty}' : '');
    final producerCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? S.t(ctx, 'add') : S.t(ctx, 'edit')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (r == null)
              TextField(
                controller: lotCtrl,
                decoration: InputDecoration(
                    labelText: '${S.t(ctx, 'lot')} (${S.t(ctx, 'lotAuto')})'),
              ),
            TextField(
                controller: modelCtrl,
                decoration: InputDecoration(labelText: S.t(ctx, 'model'))),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: S.t(ctx, 'qty')),
            ),
            TextField(
                controller: producerCtrl,
                decoration: const InputDecoration(labelText: 'Producer')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t(ctx, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t(ctx, 'save'))),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      if (r == null) {
        await Supabase.instance.client.rpc('rpc_admin_create_production', params: {
          'p_lot': lotCtrl.text.trim().isEmpty ? null : lotCtrl.text.trim(),
          'p_model': modelCtrl.text.trim(),
          'p_qty': int.tryParse(qtyCtrl.text.trim()),
          'p_intime': DateTime.now().toUtc().toIso8601String(),
          'p_producer': producerCtrl.text.trim().isEmpty ? null : producerCtrl.text.trim(),
        });
      } else {
        await Supabase.instance.client.rpc('rpc_admin_update_production', params: {
          'p_lot': r.lot,
          'p_model': modelCtrl.text.trim(),
          'p_qty': int.tryParse(qtyCtrl.text.trim()),
          'p_producer': producerCtrl.text.trim().isEmpty ? null : producerCtrl.text.trim(),
          'p_status': null,
          'p_result': null,
        });
      }
      await _loadProd();
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    }
  }

  Future<void> _confirmDeleteProduction(ProductionRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'delete')),
        content: Text('LOT ${r.lot} — ${S.t(ctx, 'voidConfirm')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t(ctx, 'cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(S.t(ctx, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      await Supabase.instance.client
          .rpc('rpc_admin_delete_production', params: {'p_lot': r.lot});
      await _loadProd();
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    }
  }

  // ---------------------------------------------------------------- 검사

  Widget _inspList() {
    return RefreshIndicator(
      onRefresh: _loadInsp,
      child: _loadingInsp && _insp.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _insp.isEmpty
              ? ListView(children: [
                  const SizedBox(height: AppSpacing.xl),
                  EmptyState(message: S.t(context, 'noData'), icon: Icons.inbox_outlined),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _insp.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final r = _insp[i];
                    return AppPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                      child: Row(
                        children: [
                          StatusChip(
                            kind: r.verdict == 'NG' ? StatusKind.fail : StatusKind.pass,
                            label: r.verdict,
                            dense: true,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('LOT ${r.lot}  ·  ${r.model}',
                                    style: Theme.of(context).textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text('${r.date} ${r.time}  ·  ${r.inspector}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: context.scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editInspection(r),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: context.status.fail),
                            onPressed: () => _confirmDeleteInspection(r),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _editInspection(RemoteRecord? r) async {
    final lotCtrl = TextEditingController(text: r?.lot ?? '');
    final caCtrl = TextEditingController(text: r?.ca ?? '');
    final inspectorCtrl = TextEditingController(text: r?.inspector ?? '');
    final barCtrl = TextEditingController(text: r?.bar ?? '');
    final modelCtrl = TextEditingController(text: r?.model ?? '');
    final racks = List<String>.from(r?.racks ?? const ['OK', 'OK', 'OK', 'OK', 'OK']);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(r == null ? S.t(ctx, 'add') : S.t(ctx, 'edit')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: lotCtrl,
                  decoration: InputDecoration(labelText: S.t(ctx, 'lot'))),
              TextField(
                  controller: caCtrl, decoration: InputDecoration(labelText: S.t(ctx, 'ca'))),
              TextField(
                  controller: inspectorCtrl,
                  decoration: InputDecoration(labelText: S.t(ctx, 'inspector'))),
              TextField(
                  controller: barCtrl,
                  decoration: InputDecoration(labelText: S.t(ctx, 'bar'))),
              TextField(
                  controller: modelCtrl,
                  decoration: InputDecoration(labelText: S.t(ctx, 'model'))),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (var i = 0; i < 5; i++)
                    FilterChip(
                      label: Text('R${i + 1} ${racks[i]}'),
                      selected: racks[i] == 'NG',
                      selectedColor: ctx.status.failContainer,
                      onSelected: (_) =>
                          setSt(() => racks[i] = racks[i] == 'OK' ? 'NG' : 'OK'),
                    ),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(S.t(ctx, 'cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(S.t(ctx, 'save'))),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      if (r == null) {
        // 신규 검사 기록은 정식 submit 경로(사진 첨부 포함) 대신 관리자 직접 입력이라
        // 사진 없이 즉시 기록 — update RPC를 uuid 신규 생성으로 재활용하지 않고
        // 기존 submit 흐름(ApiClient)을 그대로 사용해 일관성 유지.
        await widget.api.call('submit', {
          'uuid': const Uuid().v4(),
          'date': IctTime.workDate(),
          'ca': caCtrl.text.trim(),
          'inspector': inspectorCtrl.text.trim(),
          'lot': lotCtrl.text.trim(),
          'time': IctTime.nowTime(),
          'bar': barCtrl.text.trim(),
          'model': modelCtrl.text.trim(),
          'racks': racks,
          'deviceNow': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await Supabase.instance.client.rpc('rpc_admin_update_inspection', params: {
          'p_uuid': r.uuid,
          'p_ca': caCtrl.text.trim(),
          'p_inspector': inspectorCtrl.text.trim(),
          'p_lot': lotCtrl.text.trim(),
          'p_time': r.time,
          'p_bar': barCtrl.text.trim(),
          'p_model': modelCtrl.text.trim(),
          'p_rack1': racks[0],
          'p_rack2': racks[1],
          'p_rack3': racks[2],
          'p_rack4': racks[3],
          'p_rack5': racks[4],
        });
      }
      await _loadInsp();
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    }
  }

  Future<void> _confirmDeleteInspection(RemoteRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'delete')),
        content: Text('LOT ${r.lot} — ${S.t(ctx, 'voidConfirm')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t(ctx, 'cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(S.t(ctx, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      await Supabase.instance.client
          .rpc('rpc_admin_delete_inspection', params: {'p_uuid': r.uuid});
      await _loadInsp();
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    }
  }
}
