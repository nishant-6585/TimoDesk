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

  group('IntentRegistry extended intents', () {
    IntentMatch? m(String t) => reg.match(t, ctx);

    test('patrol start / end with action slot', () {
      expect(m('start patrolling the floor')?.kind, VoiceIntentKind.patrol);
      expect(m('start patrolling the floor')?.slot<String>('action'), 'start');
      expect(m('end patrol')?.slot<String>('action'), 'stop');
    });

    test('escort follow-me / stay-here', () {
      expect(m('follow me to the meeting room')?.kind, VoiceIntentKind.escort);
      expect(m('follow me to the meeting room')?.slot<String>('action'), 'start');
      expect(m('you can stay here')?.slot<String>('action'), 'stop');
    });

    test('drive direction slot', () {
      expect(m('move forward')?.kind, VoiceIntentKind.drive);
      expect(m('move forward')?.slot<String>('direction'), 'forward');
      expect(m('turn left')?.slot<String>('direction'), 'left');
    });

    test('gesture wave vs reset', () {
      expect(m('wave hello')?.slot<String>('gesture'), 'wave');
      expect(m('stand straight')?.slot<String>('gesture'), 'reset');
    });

    test('volume up / down / mute', () {
      expect(m('speak louder')?.slot<String>('action'), 'up');
      expect(m('turn it down')?.slot<String>('action'), 'down');
      expect(m('mute')?.slot<String>('action'), 'mute');
    });

    test('language extraction, gated to known languages', () {
      expect(m('can you speak in Hindi')?.kind, VoiceIntentKind.language);
      expect(m('can you speak in Hindi')?.slot<String>('language'), 'hindi');
      expect(m('switch to English')?.slot<String>('language'), 'english');
      // "switch to the front desk" is not a language change.
      expect(m('switch to the front desk')?.kind, isNot(VoiceIntentKind.language));
    });

    test('snapshot, help, resume, cancel-nav, sleep/wake', () {
      expect(m('take a photo')?.kind, VoiceIntentKind.snapshot);
      expect(m('what can you do')?.kind, VoiceIntentKind.help);
      expect(m('carry on')?.kind, VoiceIntentKind.resume);
      expect(m('I changed my mind')?.kind, VoiceIntentKind.cancelNav);
      expect(m('go to sleep')?.slot<String>('action'), 'sleep');
      expect(m('wake up')?.slot<String>('action'), 'wake');
    });

    test('bare "cancel" / "never mind" fall to the safety stop, not cancelNav', () {
      // The stop reflex owns those synonyms — the global STOP interlock halts
      // navigation anyway, so this is the safe resolution.
      expect(m('cancel')?.kind, VoiceIntentKind.stop);
      expect(m('never mind')?.kind, VoiceIntentKind.stop);
    });

    test('a saved point still beats the new verbs (no false capture)', () {
      expect(m('take me to restroom')?.slot<NavPoint>('point')?.name, 'Rest Room');
    });
  });

  group('IntentRegistry.fromCatalog', () {
    test('disabling a command in the catalog switches it off on-device', () {
      final reg = IntentRegistry.fromCatalog(const [
        CatalogCommand(intent: 'snapshot', enabled: false),
        CatalogCommand(intent: 'patrol', enabled: true),
      ]);
      // snapshot disabled → not a command (agent may answer).
      expect(reg.match('take a photo', ctx), isNull);
      // patrol still enabled.
      expect(reg.match('start patrol', ctx)?.kind, VoiceIntentKind.patrol);
      // stop is not in the catalog rows → keeps its code default (safety).
      expect(reg.match('stop', ctx)?.kind, VoiceIntentKind.stop);
    });

    test('disabling dock does not disable navigate (same code matcher)', () {
      final reg = IntentRegistry.fromCatalog(const [
        CatalogCommand(intent: 'dock', enabled: false),
      ]);
      expect(reg.match('go to the dock', ctx), isNull); // dock suppressed
      expect(reg.match('take me to restroom', ctx)?.kind, VoiceIntentKind.navigate);
    });

    test('kindByName maps catalog strings to kinds', () {
      expect(IntentRegistry.kindByName('escort'), VoiceIntentKind.escort);
      expect(IntentRegistry.kindByName('nope'), isNull);
    });
  });
}
