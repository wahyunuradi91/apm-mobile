import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/general_data/general_data_create_page.dart';
import 'features/general_data/general_data_page.dart';
import 'features/home/home_page.dart';
import 'features/home/shell_page.dart';
import 'features/profile/profile_page.dart';
import 'features/workorder/workorder_detail_page.dart';
import 'features/workorder/workorder_list_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Trigger redirect ulang setiap status auth berubah.
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading && !auth.hasValue) return '/splash';

      final loggedIn = auth.value != null;
      final atLogin = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/splash';

      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin || atSplash) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/workorder/:id',
        builder: (_, state) =>
            WorkorderDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/general-data/create/:equipmentId',
        builder: (_, state) =>
            GeneralDataCreatePage(equipmentId: int.parse(state.pathParameters['equipmentId']!)),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellPage(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/workorder',
              builder: (_, _) => const WorkorderListPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/general-data',
              builder: (_, _) => const GeneralDataPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
          ]),
        ],
      ),
    ],
  );
});
