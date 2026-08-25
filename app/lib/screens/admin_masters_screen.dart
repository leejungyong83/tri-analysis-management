import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/strings.dart';
import '../services/api_client.dart';
import '../services/master_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Masters(검사자/모델) 관리 — 관리자 전용. 추가/삭제만 지원(수정은 삭제 후 재추가).
/// rpc_admin_add_master/rpc_admin_delete_master는 로그인 세션(JWT)으로 호출해야
/// auth.uid() 관리자 검사가 통과한다 — Supabase.instance.client.rpc(...) 직접 사용.
/// 목록 새로고침(masters 조회)은 기존 앱 토큰 경로(ApiClient)를 그대로 재사용.
class AdminMastersScreen extends StatefulWidget {
  final MasterCache masters;
  final ApiClient api;
  const AdminMastersScreen({super.key, required this.masters, required this.api});

  @override
  State<AdminMastersScreen> createState() => _AdminMastersScreenState();
}

class _AdminMastersScreenState extends State<AdminMastersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _inspectorCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _inspectorCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _add(String kind, String value) async {
    if (value.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      await Supabase.instance.client.rpc('rpc_admin_add_master',
          params: {'p_kind': kind, 'p_value': value.trim()});
      await widget.masters.refresh(widget.api); // 로컬 캐시도 갱신
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String kind, String value) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final failColor = context.status.fail;
    final networkErrorMsg = S.t(context, 'networkError');
    try {
      await Supabase.instance.client.rpc('rpc_admin_delete_master',
          params: {'p_kind': kind, 'p_value': value});
      await widget.masters.refresh(widget.api);
    } catch (_) {
      messenger.showSnackBar(
          coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.masters.cached;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'masterMgmt')),
        bottom: TabBar(controller: _tab, tabs: [
          Tab(text: S.t(context, 'inspector')),
          Tab(text: S.t(context, 'model')),
        ]),
      ),
      body: TabBarView(controller: _tab, children: [
        _list('inspector', m.inspectors, _inspectorCtrl),
        _list('model', m.models, _modelCtrl),
      ]),
    );
  }

  Widget _list(String kind, List<String> values, TextEditingController ctrl) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'addNew'),
                    prefixIcon: const Icon(Icons.add),
                  ),
                  onSubmitted: (v) {
                    _add(kind, v);
                    ctrl.clear();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        _add(kind, ctrl.text);
                        ctrl.clear();
                      },
                child: Text(S.t(context, 'add')),
              ),
            ],
          ),
        ),
        Expanded(
          child: values.isEmpty
              ? EmptyState(
                  message: S.t(context, 'noData'), icon: Icons.list_alt_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: values.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final v = values[i];
                    return ListTile(
                      title: Text(v),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, color: context.status.fail),
                        onPressed: _busy ? null : () => _confirmDelete(kind, v),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(String kind, String value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'delete')),
        content: Text(value),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t(ctx, 'cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(S.t(ctx, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) _delete(kind, value);
  }
}
