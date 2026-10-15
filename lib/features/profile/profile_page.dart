import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: ApmColors.primary.withValues(alpha: 0.15),
                    foregroundColor: ApmColors.primary,
                    child: Text(
                      (user?.name.isNotEmpty ?? false) ? user!.name[0] : '?',
                    ),
                  ),
                  title: Text(user?.name ?? '-'),
                  subtitle: Text('NIK ${user?.nik ?? '-'}'),
                ),
                const Divider(),
                _Info('Email', user?.email),
                _Info('Pabrik', user?.factoryName),
                _Info('Role', user?.roles.join(', ')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: ApmColors.danger,
              side: const BorderSide(color: ApmColors.danger),
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Keluar'),
          ),
          const SizedBox(height: 24),
          Text(
            'Server: ${AppConfig.apiBaseUrl}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ApmColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(color: ApmColors.muted)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(
          (value == null || value!.isEmpty) ? '-' : value!,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
