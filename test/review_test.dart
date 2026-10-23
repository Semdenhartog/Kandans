import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/services/review_service.dart';

void main() {
  test('om een beoordeling vragen: pas na 5 eigen runs, en maar één keer', () {
    expect(ReviewService.shouldAsk(ownRuns: 4, askedBefore: false), isFalse);
    expect(ReviewService.shouldAsk(ownRuns: 5, askedBefore: false), isTrue);
    expect(ReviewService.shouldAsk(ownRuns: 12, askedBefore: false), isTrue);
    expect(ReviewService.shouldAsk(ownRuns: 12, askedBefore: true), isFalse);
  });
}
