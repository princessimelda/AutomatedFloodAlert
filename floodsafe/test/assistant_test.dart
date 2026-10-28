import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/assistant/assistant_repository.dart';
import 'package:floodsafe/assistant_screen.dart';

const question = AssistantQuestion(
  id: 'live-data',
  language: 'en',
  category: 'App help',
  question: 'Is the information live?',
);
AssistantAnswer makeAnswer({String id = 'live-data', bool expired = false}) {
  final now = DateTime.now().toUtc();
  return AssistantAnswer(
    id: id,
    language: 'en',
    question: question.question,
    answer: 'The current risk scenarios are test data.',
    source: 'FloodSafe notes',
    sourceUrl: 'https://example.com/notes',
    reviewedAt: now.subtract(const Duration(days: 2)),
    validUntil: expired
        ? now.subtract(const Duration(days: 1))
        : now.add(const Duration(days: 1)),
  );
}

class TestKnowledge implements AssistantRepository {
  bool failQuestions = false, failAnswer = false, expired = false;
  int calls = 0;
  Completer<AssistantAnswer>? pending;
  @override
  Future<List<AssistantQuestion>> questions() async {
    if (failQuestions) throw Exception('offline');
    return [question];
  }

  @override
  Future<AssistantAnswer> answer(AssistantQuestion question) async {
    calls++;
    if (failAnswer) throw Exception('withdrawn');
    if (pending != null) return pending!.future;
    return makeAnswer(expired: expired);
  }
}

class LongLivedKnowledge extends TestKnowledge {
  LongLivedKnowledge(this.answerValue);
  final AssistantAnswer answerValue;
  @override
  Future<AssistantAnswer> answer(AssistantQuestion question) async =>
      answerValue;
}

void main() {
  testWidgets('Long-lived answers survive expiry checks and expire when due', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 28);
    final answer = AssistantAnswer(
      id: question.id,
      language: question.language,
      question: question.question,
      answer: 'Published answer',
      source: 'Test source',
      sourceUrl: 'https://example.com',
      reviewedAt: now,
      validUntil: now.add(const Duration(days: 90)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantScreen(
            repository: LongLivedKnowledge(answer),
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question-live-data')));
    await tester.pumpAndSettle();
    expect(find.text('Published answer'), findsOneWidget);
    now = now.add(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(find.text('Published answer'), findsOneWidget);
    now = answer.validUntil;
    await tester.pump(const Duration(days: 1));
    expect(find.text('Published answer'), findsNothing);
    expect(find.text('Retry answer'), findsOneWidget);
  });
  Future<void> start(
    WidgetTester tester,
    AssistantRepository repository, {
    bool enlarged = false,
  }) async {
    if (enlarged) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssistantScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    final button = find.byKey(const Key('question-live-data'));
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Only catalogue questions can be asked; answers show source and review dates',
    (tester) async {
      await start(tester, TestKnowledge());
      expect(find.byType(TextField), findsNothing);
      await ask(tester);
      expect(
        find.text('The current risk scenarios are test data.'),
        findsOneWidget,
      );
      expect(find.textContaining('Source: FloodSafe notes'), findsOneWidget);
      expect(find.textContaining('Content checked:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Repeated taps do not issue duplicate answer requests', (
    tester,
  ) async {
    final repository = TestKnowledge()..pending = Completer<AssistantAnswer>();
    await start(tester, repository);
    await ask(tester);
    await ask(tester);
    expect(repository.calls, 1);
    expect(find.text('Retrieving the published answer…'), findsOneWidget);
    repository.pending!.complete(makeAnswer());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guided-answer')), findsOneWidget);
  });
  testWidgets('A withdrawn answer offers retry without fabricating a reply', (
    tester,
  ) async {
    final repository = TestKnowledge()..failAnswer = true;
    await start(tester, repository);
    await ask(tester);
    expect(find.byKey(const Key('guided-answer')), findsNothing);
    expect(find.text('Retry answer'), findsOneWidget);
    repository.failAnswer = false;
    await tester.tap(find.text('Retry answer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guided-answer')), findsOneWidget);
  });
  testWidgets('Expired answers are not displayed', (tester) async {
    await start(tester, TestKnowledge()..expired = true);
    await ask(tester);
    expect(find.byKey(const Key('guided-answer')), findsNothing);
    expect(find.text('Retry answer'), findsOneWidget);
  });
  testWidgets('Catalogue failure is recoverable', (tester) async {
    final repository = TestKnowledge()..failQuestions = true;
    await start(tester, repository);
    expect(find.text('Retry questions'), findsOneWidget);
    repository.failQuestions = false;
    await tester.tap(find.text('Retry questions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('question-live-data')), findsOneWidget);
  });
  testWidgets('Guided flow supports enlarged text on small screens', (
    tester,
  ) async {
    await start(tester, TestKnowledge(), enlarged: true);
    await ask(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('guided-answer')),
      150,
    );
    expect(find.byKey(const Key('guided-answer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
