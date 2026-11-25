import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:floodsafe/alerts/alert_inbox.dart';
import 'package:floodsafe/alerts/alert_repository.dart';
import 'package:floodsafe/data/api_repository.dart';

final epoch = DateTime.utc(2026, 11, 22, 12);
const reference = '10000000-0000-4000-8000-000000000001';

PublicAlert alert({DateTime? expiry}) => PublicAlert(
  id: reference,
  title: 'Practice notification',
  message: 'This is a controlled test.',
  action: 'Read the test message.',
  severity: 'information',
  locations: const ['Kibera'],
  issuedAt: epoch.subtract(const Duration(minutes: 1)),
  validUntil: expiry ?? epoch.add(const Duration(hours: 1)),
);

class Alerts implements AlertRepository {
  List<PublicAlert> items = [alert()];
  bool failed = false;
  int acknowledgements = 0;
  @override
  Future<List<PublicAlert>> alerts({String? placeId}) async {
    if (failed) throw Exception('offline');
    return items;
  }

  @override
  Future<void> acknowledge(String id) async {
    acknowledgements++;
  }
}

Map<String, dynamic> payload() => {
  'id': reference,
  'title': 'Practice notification',
  'message': 'Test only',
  'recommended_action': 'Read the test message.',
  'severity': 'information',
  'revision': 3,
  'issued_at': epoch.toIso8601String(),
  'valid_until': epoch.add(const Duration(hours: 1)).toIso8601String(),
  'is_demo': true,
  'locations': [
    {'id': 'kibera', 'name': 'Kibera'},
  ],
};

void main() {
  test('Public alerts preserve provenance and acknowledgement carries only the session token', () async {
    final requests = <http.Request>[];
    final api = ApiRepository(
      baseUrl: 'http://localhost:8000',
      accessToken: () => 'test-session',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.method == 'GET'
                ? [payload()]
                : {'acknowledged_at': epoch.toIso8601String()},
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final result = await api.alerts(placeId: 'kibera');
    expect(result.single.severity, 'information');
    expect(requests.first.url.queryParameters, {'place_id': 'kibera'});
    await api.acknowledge(reference);
    expect(requests.last.headers['Authorization'], 'Bearer test-session');
    expect(requests.last.body, isEmpty);
    expect(requests.last.url.toString(), isNot(contains('test-session')));
  });

  test('Malformed or unlabelled alert responses are rejected', () async {
    for (final body in [
      {...payload(), 'is_demo': false},
      {...payload(), 'severity': 'safe'},
      {...payload(), 'locations': []},
      {...payload(), 'issued_at': '2026-11-22T12:00:00'},
      {
        ...payload(),
        'valid_until': epoch
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      },
    ]) {
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((_) async => http.Response(jsonEncode([body]), 200)),
      );
      await expectLater(api.alerts(), throwsA(isA<ApiFailure>()));
      api.close();
    }
  });

  testWidgets(
    'Inbox shows area, test label, reference, action and guest sign-in',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertInbox(
              repository: Alerts(),
              clock: () => epoch,
              onSignIn: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Practice notification'), findsOneWidget);
      expect(find.text('Practice alert · INFORMATION'), findsOneWidget);
      expect(find.text('Area: Kibera'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sign in to acknowledge'), 200);
      expect(find.text('Reference: 10000000'), findsOneWidget);
      expect(find.text('What to do: Read the test message.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Acknowledge records a read once and does not remove the published alert',
    (tester) async {
      final repository = Alerts();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertInbox(
              repository: repository,
              accountId: 'owner',
              clock: () => epoch,
              onSignIn: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('I have read this alert');
      await tester.scrollUntilVisible(button, 200);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Acknowledged'), findsOneWidget);
      expect(repository.acknowledgements, 1);
      expect(find.text('Practice notification'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Expiry and failed refresh hide old alerts rather than implying safety',
    (tester) async {
      var clock = epoch;
      final repository = Alerts()
        ..items = [alert(expiry: epoch.add(const Duration(seconds: 2)))];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertInbox(
              repository: repository,
              clock: () => clock,
              onSignIn: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Practice notification'), findsOneWidget);
      clock = epoch.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Practice notification'), findsNothing);
      repository.failed = true;
      await tester.tap(find.text('Refresh alerts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alerts could not be loaded'), findsOneWidget);
      expect(find.text('Practice notification'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Inbox fits 320px with 200% text and labelled actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AlertInbox(
            repository: Alerts(),
            clock: () => epoch,
            onSignIn: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign in to acknowledge'), 250);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
