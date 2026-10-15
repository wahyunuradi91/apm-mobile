import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  if (AppConfig.appBaseUrl.isEmpty) {
    throw StateError(
      'APP_BASE_URL kosong. Jalankan dengan --dart-define-from-file=env/dev.json '
      '(salin dari env/dev.example.json).',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  runApp(const ProviderScope(child: ApmApp()));
}

class ApmApp extends ConsumerWidget {
  const ApmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'APM',
      debugShowCheckedModeBanner: false,
      theme: buildApmTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
