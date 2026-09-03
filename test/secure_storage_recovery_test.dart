import 'package:flutter_test/flutter_test.dart';
import 'package:field_worker_app/services/secure_storage_recovery.dart';

void main() {
  test('BAD_DECRYPT wipes session once, emits one non-secret event, and returns null', () async {
    var wipes = 0;
    final events = <String>[];

    final value = await readSecureValueOrRecover<String>(
      read: () async => throw Exception('BAD_DECRYPT'),
      wipeSession: () async => wipes += 1,
      log: events.add,
    );

    expect(value, isNull);
    expect(wipes, 1);
    expect(events, ['Secure-storage recovery: unreadable encrypted session cleared.']);
  });

  test('non-decrypt failures remain fail-closed and do not wipe a valid session', () async {
    var wipes = 0;
    await expectLater(
      readSecureValueOrRecover<String>(
        read: () async => throw Exception('network unavailable'),
        wipeSession: () async => wipes += 1,
        log: (_) {},
      ),
      throwsA(isA<Exception>()),
    );
    expect(wipes, 0);
  });
}
