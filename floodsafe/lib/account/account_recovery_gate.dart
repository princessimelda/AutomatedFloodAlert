import 'package:flutter/material.dart';

import 'account_repository.dart';
import 'account_screen.dart';

/// Supabase returns recovery links to the existing, allowlisted site origin.
/// A recovery session must show a password form instead of silently opening Home.
class AccountRecoveryGate extends StatelessWidget {
  const AccountRecoveryGate({
    super.key,
    required this.repository,
    required this.child,
  });
  final AccountRepository? repository;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final account = repository;
    if (account is! AccountRecoveryRepository) return child;
    return StreamBuilder<void>(
      stream: account?.changes,
      builder: (context, snapshot) {
        if ((account as AccountRecoveryRepository).passwordRecoveryRequired) {
          return AccountScreen(repository: account, resetPassword: true);
        }
        return child;
      },
    );
  }
}
