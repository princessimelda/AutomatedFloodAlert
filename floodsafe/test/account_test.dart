import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/account/account_repository.dart';
import 'package:floodsafe/account/account_screen.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/main.dart';

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

void main() {
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
