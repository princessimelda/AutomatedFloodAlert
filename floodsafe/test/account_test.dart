import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/account/account_repository.dart';
import 'package:floodsafe/account/account_screen.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/main.dart';
import 'package:floodsafe/account/account_recovery_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAccount implements AccountRepository {
  String? owner;
  final events = StreamController<void>.broadcast();
  List<SavedPlace> places = [];
  @override
  String? get userId => owner;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> signIn(String email, String password) async {
    owner = 'a';
    events.add(null);
  }

  @override
  Future<bool> signUp(String email, String password) async => false;
  @override
  Future<void> signOut() async {
    owner = null;
    events.add(null);
  }

  @override
  Future<List<SavedPlace>> savedPlaces() async => owner == null ? [] : places;
  @override
  Future<void> save(Place place) async {
    places = [SavedPlace('saved', place, false)];
  }

  @override
  Future<void> remove(String id) async {
    places = [];
  }

  @override
  Future<void> makeDefault(String id) async {
    places = [SavedPlace(places.single.id, places.single.place, true)];
  }
}

class RecoverableAccount extends FakeAccount
    implements AccountRecoveryRepository {
  Object? signInError;
  String? submittedPassword, resetEmail, confirmationEmail;
  bool recovering = false;
  @override
  bool get passwordRecoveryRequired => recovering;
  @override
  Future<void> signIn(String email, String password) async {
    submittedPassword = password;
    if (signInError != null) throw signInError!;
    await super.signIn(email, password);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    confirmationEmail = email;
  }

  @override
  Future<void> updatePassword(String password) async {
    submittedPassword = password;
    recovering = false;
    events.add(null);
  }
}

void main() {
  Future<void> showAccount(
    WidgetTester tester,
    RecoverableAccount account,
  ) async {
    addTearDown(account.events.close);
    await tester.pumpWidget(
      MaterialApp(home: AccountScreen(repository: account)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Invalid credentials have specific guidance and preserve password',
    (tester) async {
      final account = RecoverableAccount()
        ..signInError = const AuthException(
          'private server detail',
          code: 'invalid_credentials',
        );
      await showAccount(tester, account);
      await tester.enterText(
        find.byType(TextFormField).first,
        'person@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'old123');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(account.submittedPassword, 'old123');
      expect(
        find.textContaining('The email or password is incorrect.'),
        findsOneWidget,
      );
      expect(find.textContaining('private server detail'), findsNothing);
      expect(account.userId, isNull);
    },
  );
  testWidgets('Unconfirmed email gives confirmation instructions', (
    tester,
  ) async {
    final account = RecoverableAccount()
      ..signInError = const AuthException(
        'confirmation required',
        code: 'email_not_confirmed',
      );
    await showAccount(tester, account);
    await tester.enterText(
      find.byType(TextFormField).first,
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'example-password');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Confirm your email before signing in.'),
      findsOneWidget,
    );
  });
  testWidgets('Recovery actions validate email without requiring a password', (
    tester,
  ) async {
    final account = RecoverableAccount();
    await showAccount(tester, account);
    await tester.ensureVisible(find.text('Forgot password'));
    await tester.tap(find.text('Forgot password'));
    await tester.pumpAndSettle();
    expect(account.resetEmail, isNull);
    await tester.enterText(
      find.byType(TextFormField).first,
      ' person@example.com ',
    );
    await tester.ensureVisible(find.text('Forgot password'));
    await tester.tap(find.text('Forgot password'));
    await tester.pumpAndSettle();
    expect(account.resetEmail, 'person@example.com');
    expect(find.textContaining('If this email has an account'), findsOneWidget);
    await tester.ensureVisible(find.text('Resend confirmation email'));
    await tester.tap(find.text('Resend confirmation email'));
    await tester.pumpAndSettle();
    expect(account.confirmationEmail, 'person@example.com');
  });
  testWidgets(
    'Recovery session opens password form and requires matching passwords',
    (tester) async {
      final account = RecoverableAccount()..owner = 'a';
      addTearDown(account.events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountRecoveryGate(
            repository: account,
            child: const Text('Home content'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      account.recovering = true;
      account.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Set a new password'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'replacement-password',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'different-password',
      );
      await tester.ensureVisible(find.text('Save new password'));
      await tester.tap(find.text('Save new password'));
      await tester.pumpAndSettle();
      expect(account.submittedPassword, isNull);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).last,
        'replacement-password',
      );
      await tester.ensureVisible(find.text('Save new password'));
      await tester.tap(find.text('Save new password'));
      await tester.pumpAndSettle();
      expect(account.submittedPassword, 'replacement-password');
      expect(find.text('Home content'), findsOneWidget);
    },
  );
  testWidgets('An open account page reacts to recovery for the same user', (
    tester,
  ) async {
    final account = RecoverableAccount()..owner = 'a';
    await showAccount(tester, account);
    account.recovering = true;
    account.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.text('Save new password'), findsOneWidget);
  });
  testWidgets('Sign in, save, default and remove a supported place', (
    tester,
  ) async {
    final account = FakeAccount();
    addTearDown(account.events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(repository: account, selected: samplePlaces.first),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'example-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Your saved places'), findsOneWidget);
    await tester.tap(find.text('Save Kibera'));
    await tester.pumpAndSettle();
    expect(find.text('View Kibera'), findsOneWidget);
    await tester.tap(find.text('Make Kibera default'));
    await tester.pumpAndSettle();
    expect(find.text('Default place'), findsOneWidget);
    await tester.tap(find.text('Remove Kibera'));
    await tester.pumpAndSettle();
    expect(find.text('View Kibera'), findsNothing);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to save places'), findsOneWidget);
  });
  testWidgets('Restored default opens and sign-out clears it', (tester) async {
    final account = FakeAccount()
      ..owner = 'a'
      ..places = [SavedPlace('saved', samplePlaces.first, true)];
    addTearDown(account.events.close);
    await tester.pumpWidget(FloodSafeApp(accountRepository: account));
    await tester.pumpAndSettle();
    expect(find.text('Kibera'), findsOneWidget);
    await account.signOut();
    await tester.pumpAndSettle();
    expect(find.text('No place selected'), findsOneWidget);
  });
}
