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

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this.client, {this.confirmationRedirectUrl});
  final SupabaseClient client;
  final String? confirmationRedirectUrl;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<void> get changes => client.auth.onAuthStateChange.map((_) {});
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: confirmationRedirectUrl,
    );
    return response.session != null;
  }

  @override
  Future<void> signOut() => client.auth.signOut();
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
