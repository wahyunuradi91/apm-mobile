import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';

/// Meniru resources/js/Pages/Auth/Login.vue: satu tombol "Masuk menggunakan OneKey"
/// yang membuka halaman login Keycloak (sama dengan web).
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset('assets/images/logo.png', height: 72),
                          const SizedBox(height: 24),
                          Text(
                            'Masuk Sistem',
                            textAlign: TextAlign.center,
                            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Selamat datang di Asset Performance Monitoring',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(color: ApmColors.muted),
                          ),
                          const SizedBox(height: 24),
                          if (auth.hasError) ...[
                            _ErrorAlert(apiErrorMessage(auth.error!)),
                            const SizedBox(height: 16),
                          ],
                          FilledButton(
                            onPressed: loading
                                ? null
                                : () => ref.read(authControllerProvider.notifier).login(),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (loading)
                                  const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  Image.asset('assets/images/logo_onekey.png', height: 22),
                                const SizedBox(width: 10),
                                Text(
                                  loading
                                      ? 'Menghubungkan ke OneKey…'
                                      : 'Masuk menggunakan OneKey',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          Text.rich(
                            const TextSpan(
                              text: 'Gunakan akun ',
                              children: [
                                TextSpan(
                                  text: 'OneKey',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: ApmColors.primary,
                                  ),
                                ),
                                TextSpan(text: ' (SSO) PT Petrokimia Gresik'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(color: ApmColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '© ${DateTime.now().year} PT Petrokimia Gresik',
                style: text.bodySmall?.copyWith(color: ApmColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorAlert extends StatelessWidget {
  const _ErrorAlert(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ApmColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: ApmColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: ApmColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
