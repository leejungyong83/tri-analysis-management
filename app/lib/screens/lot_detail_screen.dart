import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/strings.dart';
import '../models/inspection.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// LOT 상세 — Rack 1~5 결과, 사진 링크, rework 여부, void(무효화).
///
/// 기록 수정은 non-goal — 오입력은 무효화 후 재입력 (audit 보존, 행 삭제 없음).
class LotDetailScreen extends StatefulWidget {
  final ApiClient api;
  final RemoteRecord record;
  final bool isAdmin; // 무효화(void)는 관리자만 — 조회는 전 역할 공통

  const LotDetailScreen({
    super.key,
    required this.api,
    required this.record,
    this.isAdmin = false,
  });

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  bool _voiding = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final ng = r.verdict == 'NG';
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(title: Text('LOT ${r.lot}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
        children: [
          if (r.voided)
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: context.status.neutralContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: context.status.onNeutralContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Text(S.t(context, 'voided'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.status.onNeutralContainer)),
                ],
              ),
            ),

          // ── 판정 요약 (색 + 텍스트) ──────────────────────────────────────
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(S.t(context, 'verdict'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    StatusChip(
                      kind: ng ? StatusKind.fail : StatusKind.pass,
                      label: r.verdict,
                      solid: true,
                    ),
                    if (r.rework) ...[
                      const SizedBox(width: AppSpacing.sm),
                      StatusChip(
                        kind: StatusKind.process,
                        label: '${S.t(context, 'rework')} ${r.reworkLot}',
                        icon: Icons.build_rounded,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(S.t(context, 'result'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var i = 0; i < r.racks.length; i++)
                      StatusChip(
                        kind: r.racks[i] == 'NG'
                            ? StatusKind.fail
                            : StatusKind.pass,
                        label: 'R${i + 1} ${r.racks[i]}',
                        dense: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 기록 정보 ────────────────────────────────────────────────────
          AppPanel(
            child: Column(
              children: [
                _kv(context, S.t(context, 'date'), '${r.date} ${r.time}'),
                _kv(context, S.t(context, 'ca'), r.ca),
                _kv(context, S.t(context, 'inspector'), r.inspector),
                _kv(context, S.t(context, 'lot'), r.lot),
                _kv(context, S.t(context, 'bar'), r.bar),
                _kv(context, S.t(context, 'model'), r.model, last: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 사진 (Rack별) ────────────────────────────────────────────────
          SectionHeader('${S.t(context, 'photos')} (Rack별)'),
          const SizedBox(height: AppSpacing.sm),
          AppPanel(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < r.photos.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _rackPhotoTile(context, i, r.photos[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          if (!r.voided && widget.isAdmin)
            OutlinedButton.icon(
              onPressed: _voiding ? null : _confirmVoid,
              icon: _voiding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.block, size: 18),
              label: Text(S.t(context, 'voidAction')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }

  /// Rack별 사진 1행 — 업로드 대기면 표시, 완료면 열기 링크.
  Widget _rackPhotoTile(BuildContext context, int i, String photo) {
    final pending = photo == 'pending' || photo.isEmpty;
    final st = context.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pending ? st.processContainer : st.passContainer,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Text('${i + 1}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color:
                        pending ? st.onProcessContainer : st.onPassContainer)),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text('Rack ${i + 1}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (pending)
            StatusChip(
              kind: StatusKind.process,
              label: S.t(context, 'photoPending'),
              icon: Icons.cloud_upload_rounded,
              dense: true,
            )
          else
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(photo),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(S.t(context, 'openLink')),
            ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool last = false}) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(v, style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmVoid() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failColor = context.status.fail;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'voidAction')),
        content: Text(S.t(ctx, 'voidConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(S.t(ctx, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _voiding = true);
    try {
      await widget.api.call('void', {
        'uuid': widget.record.uuid,
        'date': widget.record.date,
      });
      navigator.pop(true); // 목록 새로고침 트리거
    } on ApiException catch (e) {
      messenger.showSnackBar(
          coloredSnackBar(e.message, failColor, Icons.error_outline));
      setState(() => _voiding = false);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(coloredSnackBar(
            S.t(context, 'networkError'), failColor, Icons.error_outline));
        setState(() => _voiding = false);
      }
    }
  }
}
