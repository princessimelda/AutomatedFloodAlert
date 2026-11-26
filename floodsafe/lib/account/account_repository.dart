import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../dashboard/dashboard_data.dart';

class SavedPlace {
  const SavedPlace(this.id, this.place, this.isDefault);
  final String id;
  final Place place;
  final bool isDefault;
}

abstract interface class AccountRepository {
  String? get userId;
  Stream<void> get changes;
  Future<void> signIn(String email, String password);
  Future<bool> signUp(String email, String password);
  Future<void> signOut();
  Future<List<SavedPlace>> savedPlaces();
  Future<void> save(Place place);
  Future<void> remove(String id);
  Future<void> makeDefault(String id);
}

abstract interface class AccountRecoveryRepository {
  bool get passwordRecoveryRequired;
  Future<void> resendConfirmation(String email);
  Future<void> requestPasswordReset(String email);
  Future<void> updatePassword(String password);
}

class SupabaseAccountRepository
    implements AccountRepository, AccountRecoveryRepository {
  SupabaseAccountRepository(this.client, {this.confirmationRedirectUrl}) {
    _changes = client.auth.onAuthStateChange.map((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryRequired = true;
      } else if (state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.userUpdated) {
        _passwordRecoveryRequired = false;
      }
    }).asBroadcastStream();
  }
  final SupabaseClient client;
  final String? confirmationRedirectUrl;
  late final Stream<void> _changes;
  bool _passwordRecoveryRequired = false;
  @override
  bool get passwordRecoveryRequired => _passwordRecoveryRequired;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<void> get changes => _changes;
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: confirmationRedirectUrl,
    );
    return response.session != null;
  }

  @override
  Future<void> signOut() => client.auth.signOut();
  @override
  Future<void> resendConfirmation(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: confirmationRedirectUrl,
    );
  }

  @override
  Future<void> requestPasswordReset(String email) => client.auth
      .resetPasswordForEmail(email.trim(), redirectTo: confirmationRedirectUrl);

  @override
  Future<void> updatePassword(String password) async {
    if (client.auth.currentSession == null) {
      throw const AuthException('Sign in again.', code: 'session_not_found');
    }
    await client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<List<SavedPlace>> savedPlaces() async {
    final owner = userId;
    if (owner == null) return [];
    final rows = await client
        .from('saved_places')
        .select('id,is_default,places!inner(id,name,is_demo)')
        .eq('user_id', owner)
        .order('created_at');
    if (owner != userId) return [];
    return rows.map((row) {
      final place = row['places'] as Map<String, dynamic>;
      return SavedPlace(
        row['id'] as String,
        Place(
          id: place['id'] as String,
          name: place['name'] as String,
          isDemo: place['is_demo'] as bool,
        ),
        row['is_default'] as bool,
      );
    }).toList();
  }

  @override
  Future<void> save(Place place) async {
    final owner = userId;
    if (owner == null) throw StateError('Sign in required');
    await client
        .from('saved_places')
        .upsert(
          {'user_id': owner, 'place_id': place.id, 'label': place.name},
          onConflict: 'user_id,place_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> remove(String id) async {
    final owner = userId;
    if (owner == null) throw StateError('Sign in required');
    await client
        .from('saved_places')
        .delete()
        .eq('id', id)
        .eq('user_id', owner);
  }

  @override
  Future<void> makeDefault(String id) =>
      client.rpc('set_default_place', params: {'target_id': id});
}
