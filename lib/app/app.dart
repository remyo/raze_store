import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/app/theme_mode_controller.dart';

class RazeStoreApp extends ConsumerWidget {
  const RazeStoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Raze Store',
      debugShowCheckedModeBanner: false,
      locale: const Locale('en', 'PH'),
      supportedLocales: const [Locale('en', 'PH')],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
