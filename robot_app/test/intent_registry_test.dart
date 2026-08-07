import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/services/intent_registry.dart';
import 'package:robot_app/services/nav_points_api.dart';

NavPoint _pt(String name) => NavPoint(
      id: name, name: name, x: 0, y: 0, z: 0, rotation: 0,
      kind: 'navigation', sortOrder: 0,
    );

void main() {
  final reg = IntentRegistry.standard;
  final ctx = IntentContext(navPoints: [_pt('Rest Room'), _pt('Nishant')]);

  group('IntentRegistry dispatch', () {
    test('stop wins and returns stop', () {
      expect(reg.match('stop', ctx)?.kind, VoiceIntentKind.stop);
      expect(reg.match('that\'s enough', ctx)?.kind, VoiceIntentKind.stop);
    });

    test('navigation resolves a saved point (fuzzy)', () {
      final m = reg.match('take me to restroom', ctx);
      expect(m?.kind, VoiceIntentKind.navigate);
      expect(m?.slot<NavPoint>('point')?.name, 'Rest Room');
    });

    test('dock is its own intent, not a point', () {
      final m = reg.match('go to the dock', ctx);
      expect(m?.kind, VoiceIntentKind.dock);
      expect(m?.slot<NavPoint>('point'), isNull);
    });

    test('unknown place is navigate with a null point + heard text', () {
      final m = reg.match('take me to the moon', ctx);
      expect(m?.kind, VoiceIntentKind.navigate);
      expect(m?.slot<NavPoint>('point'), isNull);
      expect(m?.slot<String>('heard'), 'moon');
    });

    test('persona rename carries the new name', () {
      final m = reg.match('change your name to Rocky', ctx);
      expect(m?.kind, VoiceIntentKind.persona);
      expect(m?.slot<String>('personName'), 'Rocky');
    });

    test('check-in carries the host', () {
      final m = reg.match('I am here to see Vishal', ctx);
      expect(m?.kind, VoiceIntentKind.checkin);
      expect((m?.slot<String>('host') ?? '').toLowerCase(), contains('vishal'));
    });

    test('chit-chat is not a command (agent answers)', () {
      expect(reg.match('what time do you close', ctx), isNull);
    });

    test('priority: "stop" never gets mis-claimed by a later intent', () {
      // The stop intent has the lowest priority number → checked first.
      expect(reg.intents.first.id, 'system.stop');
      expect(reg.match('stop talking', ctx)?.kind, VoiceIntentKind.stop);
    });
  });
}
