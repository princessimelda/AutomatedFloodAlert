import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:floodsafe/account/account_repository.dart';
import 'package:floodsafe/account/account_errors.dart';

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
    'Signup and sign-in submit the same email and unmodified password',
    () async {
      final submitted = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-public-key',
        httpClient: MockClient((request) async {
          submitted.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (request.url.path.endsWith('/signup')) {
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
          }
          return http.Response(
            jsonEncode({
              'code': 'invalid_credentials',
              'msg': 'Invalid login credentials',
            }),
            400,
          );
        }),
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAccountRepository(client);
      const password = '  Example-Pässword!42  ';
      await repository.signUp(' person@example.com ', password);
      await expectLater(
        repository.signIn(' person@example.com ', password),
        throwsA(isA<AuthException>()),
      );
      expect(submitted, hasLength(2));
      for (final fields in submitted) {
        expect(fields['email'], 'person@example.com');
        expect(fields['password'], password);
      }
      expect(repository.userId, isNull);
    },
  );
  test(
    'Authentication failures use actionable messages without server details',
    () {
      expect(
        accountErrorMessage(
          const AuthException('secret detail', code: 'invalid_credentials'),
        ),
        contains('email or password is incorrect'),
      );
      expect(
        accountErrorMessage(
          const AuthException('secret detail', code: 'email_not_confirmed'),
        ),
        contains('Confirm your email'),
      );
      expect(
        accountErrorMessage(
          const AuthException('secret detail', statusCode: '429'),
        ),
        contains('Too many attempts'),
      );
      expect(
        accountErrorMessage(
          const AuthException('secret detail', code: 'otp_expired'),
        ),
        contains('expired'),
      );
      expect(
        accountErrorMessage(AuthRetryableFetchException()),
        contains('internet connection'),
      );
      expect(
        accountErrorMessage(const AuthException('secret detail')),
        isNot(contains('secret detail')),
      );
    },
  );
  test(
    'Recovery emails use the existing site origin and signup confirmation type',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-public-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAccountRepository(
        client,
        confirmationRedirectUrl: 'https://floodsafe-d1m3.onrender.com',
      );
      await repository.requestPasswordReset(' person@example.com ');
      await repository.resendConfirmation(' person@example.com ');
      expect(requests.map((request) => request.url.path), [
        '/auth/v1/recover',
        '/auth/v1/resend',
      ]);
      for (final request in requests) {
        expect(
          request.url.queryParameters['redirect_to'],
          'https://floodsafe-d1m3.onrender.com',
        );
        expect(jsonDecode(request.body)['email'], 'person@example.com');
      }
      expect(jsonDecode(requests.last.body)['type'], 'signup');
      expect(repository.userId, isNull);
      await expectLater(
        repository.updatePassword('new-password'),
        throwsA(isA<AuthException>()),
      );
    },
  );

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
