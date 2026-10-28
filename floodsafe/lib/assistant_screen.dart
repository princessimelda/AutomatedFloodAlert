import 'dart:async';

import 'package:flutter/material.dart';

import 'assistant/assistant_repository.dart';
import 'ui.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    this.repository = const EmptyAssistantRepository(),
    this.clock = DateTime.now,
  });
  final AssistantRepository repository;
  final DateTime Function() clock;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _scroll = ScrollController();
  List<AssistantQuestion> _questions = [];
  AssistantQuestion? _selected;
  AssistantAnswer? _answer;
  bool _loading = true,
      _answerLoading = false,
      _catalogueError = false,
      _answerError = false;
  int _catalogueRequest = 0, _answerRequest = 0;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final request = ++_catalogueRequest;
    _answerRequest++;
    _expiry?.cancel();
    setState(() {
      _loading = true;
      _catalogueError = false;
      _answer = null;
      _selected = null;
      _answerLoading = false;
      _answerError = false;
      _questions = [];
    });
    try {
      final questions = await widget.repository.questions().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted || request != _catalogueRequest) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _catalogueRequest) return;
      setState(() {
        _catalogueError = true;
        _loading = false;
      });
    }
  }

  Future<void> _ask(AssistantQuestion question) async {
    if (_answerLoading) return;
    final request = ++_answerRequest;
    _expiry?.cancel();
    setState(() {
      _selected = question;
      _answer = null;
      _answerError = false;
      _answerLoading = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final answer = await widget.repository
          .answer(question)
          .timeout(const Duration(seconds: 12));
      if (!mounted || request != _answerRequest) return;
      if (answer.id != question.id ||
          answer.language != question.language ||
          !answer.current(widget.clock().toUtc())) {
        throw StateError(
          'Answer does not match the question or is no longer current.',
        );
      }
      setState(() {
        _answer = answer;
        _answerLoading = false;
      });
      _scheduleExpiry();
    } catch (_) {
      if (!mounted || request != _answerRequest) return;
      setState(() {
        _answerError = true;
        _answerLoading = false;
      });
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final answer = _answer;
    if (!mounted || answer == null) return;
    final now = widget.clock().toUtc();
    if (!answer.current(now)) {
      setState(() {
        _answer = null;
        _answerError = true;
      });
      return;
    }
    final remaining = answer.validUntil.difference(now);
    // Browser setTimeout overflows above ~24.8 days. Recheck long-lived
    // content in bounded intervals rather than expiring it immediately.
    const interval = Duration(days: 1);
    _expiry = Timer(
      remaining > interval ? interval : remaining,
      _scheduleExpiry,
    );
  }

  @override
  void dispose() {
    _catalogueRequest++;
    _answerRequest++;
    _expiry?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Semantics(
            header: true,
            child: Text('FloodSafe guide', style: titleStyle(28)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose a question. Answers come from FloodSafe’s published knowledge base, not generated AI. This guide explains the app; it cannot confirm current flood conditions.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 20),
          if (_selected != null)
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _answer?.question ?? _selected!.question,
                      style: titleStyle(22),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_answerLoading)
                    Semantics(
                      liveRegion: true,
                      child: const Text('Retrieving the published answer…'),
                    ),
                  if (_answerError) ...[
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'This answer could not be retrieved or is no longer available. No replacement answer has been generated.',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _ask(_selected!),
                      child: const Text('Retry answer'),
                    ),
                    TextButton(
                      onPressed: _loadQuestions,
                      child: const Text('Refresh questions'),
                    ),
                  ],
                  if (_answer != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _answer!.answer,
                        key: const Key('guided-answer'),
                        style: const TextStyle(height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      'Source: ${_answer!.source}\n${_answer!.sourceUrl}',
                      style: const TextStyle(color: muted, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Content checked: ${_date(_answer!.reviewedAt)}\nReview due: ${_date(_answer!.validUntil)}',
                      style: const TextStyle(color: muted, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text('Choose a question', style: titleStyle(23)),
          ),
          const SizedBox(height: 12),
          if (_loading)
            Semantics(
              liveRegion: true,
              child: const Text('Loading available questions…'),
            ),
          if (_catalogueError) ...[
            Semantics(
              liveRegion: true,
              child: const Text(
                'Could not load questions. You can still open preparedness steps from Home.',
              ),
            ),
            TextButton(
              onPressed: _loadQuestions,
              child: const Text('Retry questions'),
            ),
          ] else if (!_loading && _questions.isEmpty) ...[
            const Text(
              'No published questions are available right now. Connect to the backend or refresh later.',
            ),
            TextButton(
              onPressed: _loadQuestions,
              child: const Text('Refresh questions'),
            ),
          ],
          ..._questions.map(
            (question) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                key: Key('question-${question.id}'),
                onPressed: _answerLoading ? null : () => _ask(question),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.all(16),
                ),
                child: Text(
                  question.question,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Only the listed questions are supported. No chat messages or conversations are saved.',
            style: TextStyle(color: muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.toUtc().toIso8601String().substring(0, 10)} UTC';
