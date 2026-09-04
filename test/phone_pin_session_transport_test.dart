import 'package:flutter_test/flutter_test.dart';
import 'package:field_worker_app/services/api_service.dart';

void main() {
  group('phone/PIN session transport', () {
    test('adds only the explicit worker-session header for a phone/PIN credential', () {
      final headers = ApiService.buildPhonePinHeaders('candidate-session');

      expect(headers['Content-Type'], 'application/json');
      expect(headers['X-Field-Worker-Session'], 'candidate-session');
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('does not emit a session header when phone/PIN credential is absent', () {
      final headers = ApiService.buildPhonePinHeaders(null);

      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('X-Field-Worker-Session'), isFalse);
    });

    test('sends expired phone/PIN sessions back to worker selection', () {
      expect(ApiService.loginRouteForSessionKind('fieldManager'), '/select-worker');
      expect(ApiService.loginRouteForSessionKind(null), '/select-worker');
    });

    test('preserves supervisor 401 routing for Survey-bearer pickup sessions', () {
      expect(ApiService.loginRouteForSessionKind('supervisor'), '/supervisor-login');
    });
  });
}
