import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';

import '../application/onboarding_providers.dart';

class AppStartupGate extends ConsumerStatefulWidget {
  const AppStartupGate({super.key});

  @override
  ConsumerState<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends ConsumerState<AppStartupGate> {
  bool _redirectScheduled = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(onboardingControllerProvider);

    return status.when(
      loading: () => const AppPageScaffold(
        body: AppLoadingState(message: 'Opening your store…'),
      ),
      error: (error, stackTrace) => AppPageScaffold(
        body: AppErrorState(
          title: 'Could not open store setup',
          message: 'Check the device storage and try again.',
          onRetry: () {
            setState(() => _redirectScheduled = false);
            ref.invalidate(onboardingControllerProvider);
          },
        ),
      ),
      data: (isComplete) {
        _scheduleRedirect(isComplete ? '/products' : '/setup');
        return const AppPageScaffold(
          body: AppLoadingState(message: 'Opening your store…'),
        );
      },
    );
  }

  void _scheduleRedirect(String location) {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(location);
    });
  }
}
