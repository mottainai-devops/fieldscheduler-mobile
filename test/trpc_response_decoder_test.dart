import 'package:flutter_test/flutter_test.dart';
import 'package:field_worker_app/services/trpc_response_decoder.dart';

void main() {
  test('accepts an unwrapped tRPC object response', () {
    final result = requireMapResponse(
      {'success': true, 'violation': {'id': 42}},
      'compliance.createViolation',
    );
    expect(result['success'], isTrue);
    expect((result['violation'] as Map)['id'], 42);
  });

  test('rejects a list transport shape with a clear contract error', () {
    expect(
      () => requireMapResponse([], 'compliance.createViolation'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('expected object'),
        ),
      ),
    );
  });
}
