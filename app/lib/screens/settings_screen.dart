import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/strings.dart';
import '../services/api_client.dart';
import '../services/master_cache.dart';
import '../services/sync_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// 설정 — 언어 전환(vi/ko), 화면 테마, 검사자 선택(로그인 없음), 서버 URL/토큰,
/// 동기화 상태(대기 건수·경고·수동 동기화).
class SettingsScreen extends StatefulWidget {
  final ApiClient api;
  final MasterCache masters;
  final SyncQueue queue;
  final void Function(String locale) onLocaleChanged;
  final void Function(String themeMode) onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.api,
    required this.masters,
    required this.queue,
    required this.onLocaleChanged,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tokenCtrl;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: AppSettings.token);
    widget.queue.addListener(_onQueue);
  }

  void _onQueue() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.queue.removeListener(_onQueue);
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.masters.cached;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      children: [
        // ── 화면(언어 + 테마) ────────────────────────────────────────────
        AppPanel(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(S.t(context, 'language')),
              RadioGroup<String>(
                groupValue: AppSettings.locale,
                onChanged: (v) {
                  if (v != null) {
                    AppSettings.locale = v;
                    widget.onLocaleChanged(v);
                  }
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(
                        value: 'vi',
                        contentPadding: EdgeInsets.zero,
                        title: Text('Tiếng Việt')),
                    RadioListTile<String>(
                        value: 'ko',
                        contentPadding: EdgeInsets.zero,
                        title: Text('한국어')),
                  ],
                ),
              ),
              const Divider(),
              SectionHeader(S.t(context, 'appearance')),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<String>(
                groupValue: AppSettings.themeMode,
                onChanged: (v) {
                  if (v != null) setState(() => widget.onThemeChanged(v));
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'system',
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.brightness_auto_outlined),
                      title: Text(S.t(context, 'themeSystem')),
                    ),
                    RadioListTile<String>(
                      value: 'light',
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.light_mode_outlined),
                      title: Text(S.t(context, 'themeLight')),
                    ),
                    RadioListTile<String>(
                      value: 'dark',
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: Text(S.t(context, 'themeDark')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── 검사자 선택 (이름 선택만 — 로그인 없음, 스펙 확정) ────────────
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(S.t(context, 'inspector')),
              const SizedBox(height: AppSpacing.sm + 2),
              DropdownButtonFormField<String>(
                initialValue: m.inspectors.contains(AppSettings.inspector) &&
                        AppSettings.inspector.isNotEmpty
                    ? AppSettings.inspector
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: S.t(context, 'notSet'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                items: [
                  for (final p in m.inspectors)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => AppSettings.inspector = v ?? ''),
              ),
              const SizedBox(height: AppSpacing.sm + 2),
              OutlinedButton.icon(
                onPressed: _refreshing ? null : _refreshMasters,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(S.t(context, 'refreshMasters')),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── 서버 설정 (Supabase 앱 토큰만 — URL/키는 앱에 고정, 재빌드 불요) ──
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(S.t(context, 'appToken')),
              const SizedBox(height: AppSpacing.sm + 2),
              TextField(
                controller: _tokenCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: S.t(context, 'appToken'),
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () {
                  AppSettings.token = _tokenCtrl.text;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(S.t(context, 'settingsSaved')),
                    backgroundColor: context.status.pass,
                  ));
                },
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(S.t(context, 'save')),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── 동기화 상태 ──────────────────────────────────────────────────
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(S.t(context, 'syncStatus')),
              const SizedBox(height: AppSpacing.sm),
              if (widget.queue.warning)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.status.failContainer,
                    border: Border.all(
                        color: context.status.fail.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: context.status.onFailContainer, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(S.t(context, 'syncWarning'),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: context.status.onFailContainer)),
                      ),
                    ],
                  ),
                ),
              _syncTile(
                context,
                icon: Icons.receipt_long_outlined,
                label: S.t(context, 'pendingRecords'),
                count: widget.queue.pendingRecords,
              ),
              _syncTile(
                context,
                icon: Icons.photo_outlined,
                label: S.t(context, 'pendingPhotos'),
                count: widget.queue.pendingPhotos,
              ),
              const SizedBox(height: AppSpacing.sm + 2),
              OutlinedButton.icon(
                onPressed: () => widget.queue.processQueue(),
                icon: const Icon(Icons.sync, size: 18),
                label: Text(S.t(context, 'syncNow')),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _syncTile(BuildContext context,
      {required IconData icon, required String label, required int count}) {
    final active = count > 0;
    final tone = active ? StatusKind.process : StatusKind.pass;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium)),
          StatusChip(
            kind: tone,
            label: '$count',
            icon: active ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded,
            dense: true,
          ),
        ],
      ),
    );
  }

  Future<void> _refreshMasters() async {
    final messenger = ScaffoldMessenger.of(context);
    final networkError = S.t(context, 'networkError');
    final failColor = context.status.fail;
    setState(() => _refreshing = true);
    try {
      await widget.masters.refresh(widget.api);
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(networkError), backgroundColor: failColor));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}
