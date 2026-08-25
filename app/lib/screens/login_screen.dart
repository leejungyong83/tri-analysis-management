import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/strings.dart';
import '../theme/app_theme.dart';

/// 앱 접근 게이트 — 이메일/비밀번호 로그인 (Supabase Auth).
/// 이메일·비밀번호 모두 Supabase 대시보드(Authentication → Users)에서 자유롭게 지정한 값 그대로 사용
/// (검사자 이름 선택은 로그인과 무관하게 기존 그대로 유지 — 이건 "누가 이 앱을 열 수 있는가"만 통제).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _idCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pw,
      );
      // 성공 시 main.dart의 onAuthStateChange 리스너가 화면 전환을 처리한다.
    } on AuthException catch (_) {
      if (mounted) setState(() => _error = S.t(context, 'loginFailed'));
    } catch (_) {
      if (mounted) setState(() => _error = S.t(context, 'networkError'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Image.asset('assets/logo.png', width: 56, height: 56),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(S.t(context, 'loginTitle'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _idCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: S.t(context, 'loginId'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: S.t(context, 'loginPw'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm + 2),
                    Text(_error!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: context.status.fail)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(S.t(context, 'loginButton')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
