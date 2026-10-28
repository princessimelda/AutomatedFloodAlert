import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:floodsafe/account/account_repository.dart';

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test(
    'Signup requests the preview origin without creating a fake session',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-public-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/signup');
          expect(
            request.url.queryParameters['redirect_to'],
            'http://127.0.0.1:8765',
          );
          expect(jsonDecode(request.body)['email'], 'person@example.com');
          return http.Response(
            jsonEncode({
              'id': '10000000-0000-4000-8000-000000000001',
              'email': 'person@example.com',
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-10-28T00:00:00Z',
            }),
            200,
          );
        }),
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAccountRepository(
        client,
        confirmationRedirectUrl: 'http://127.0.0.1:8765',
      );
      expect(
        await repository.signUp('person@example.com', 'example-password'),
        isFalse,
      );
      expect(repository.userId, isNull);
    },
  );
}
