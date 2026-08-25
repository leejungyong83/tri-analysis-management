import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 계정 관리(관리자 전용) — 로그인 계정별 역할(관리자/검사자) 조회·변경.
/// rpc_list_users/rpc_set_user_role은 anon key가 아니라 "로그인한 관리자의 실제
/// 세션"으로 호출해야 하므로 Supabase.instance.client.rpc(...)를 직접 사용한다
/// (기존 ApiClient는 앱 토큰 기반 별개 경로 — 여기선 쓰지 않음).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = const [];
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('rpc_list_users');
      setState(() => _users = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {
      if (mounted) {
        setState(() => _error = S.t(context, 'accountMgmtLoadFailed'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRole(String userId, String newRole) async {
    setState(() => _updating.add(userId));
    final messenger = ScaffoldMessenger.of(context);
    final roleChangedMsg = S.t(context, 'roleChanged');
    final networkErrorMsg = S.t(context, 'networkError');
    final passColor = context.status.pass;
    final failColor = context.status.fail;
    try {
      await Supabase.instance.client.rpc('rpc_set_user_role', params: {
        'target_user_id': userId,
        'new_role': newRole,
      });
      messenger.showSnackBar(SnackBar(
        content: Text(roleChangedMsg),
        backgroundColor: passColor,
      ));
      await _load();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            coloredSnackBar(networkErrorMsg, failColor, Icons.error_outline));
      }
    } finally {
      if (mounted) setState(() => _updating.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'accountMgmt'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: AppSpacing.xl),
                    EmptyState(message: _error!, icon: Icons.error_outline),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _users.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _userTile(context, _users[i]),
                  ),
      ),
    );
  }

  Widget _userTile(BuildContext context, Map<String, dynamic> u) {
    final id = u['id'] as String;
    final email = '${u['email']}';
    final role = '${u['role']}';
    final isAdmin = role == 'admin';
    final busy = _updating.contains(id);
    return AppPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Icon(
            isAdmin ? Icons.shield_outlined : Icons.person_outline,
            color: isAdmin ? context.status.info : context.scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(email,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (busy)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            DropdownButton<String>(
              value: role,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                    value: 'inspector', child: Text(S.t(context, 'roleInspector'))),
                DropdownMenuItem(
                    value: 'admin', child: Text(S.t(context, 'roleAdmin'))),
              ],
              onChanged: (v) {
                if (v != null && v != role) _setRole(id, v);
              },
            ),
        ],
      ),
    );
  }
}
