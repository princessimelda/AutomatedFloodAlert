class AssistantQuestion {
  const AssistantQuestion({
    required this.id,
    required this.language,
    required this.category,
    required this.question,
  });
  final String id;
  final String language;
  final String category;
  final String question;
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.id,
    required this.language,
    required this.question,
    required this.answer,
    required this.source,
    required this.sourceUrl,
    required this.reviewedAt,
    required this.validUntil,
  });
  final String id;
  final String language;
  final String question;
  final String answer;
  final String source;
  final String sourceUrl;
  final DateTime reviewedAt;
  final DateTime validUntil;
  bool current(DateTime now) =>
      !now.isBefore(reviewedAt) && now.isBefore(validUntil);
}

abstract interface class AssistantRepository {
  Future<List<AssistantQuestion>> questions();
  Future<AssistantAnswer> answer(AssistantQuestion question);
}

class EmptyAssistantRepository implements AssistantRepository {
  const EmptyAssistantRepository();
  @override
  Future<List<AssistantQuestion>> questions() async => [];
  @override
  Future<AssistantAnswer> answer(AssistantQuestion question) async =>
      throw StateError('No knowledge service connected.');
}
