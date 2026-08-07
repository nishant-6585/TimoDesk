import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/services/nav_voice.dart';
import 'package:robot_app/services/nav_points_api.dart';

NavPoint _pt(String name) => NavPoint(
      id: name,
      name: name,
      x: 0,
      y: 0,
      z: 0,
      rotation: 0,
      kind: 'navigation',
      sortOrder: 0,
    );

void main() {
  final points = [_pt('Nishant Desk'), _pt('Reception')];

  group('NavVoice dock command', () {
    for (final phrase in const [
      'go to the dock',
      'navigate to the dock',
      'return to the dock',
      'go charge',
      'go and recharge',
      'dock yourself',
      'go home',
      'Mikee, please go to the dock now', // substring, mid-sentence
    ]) {
      test('"$phrase" → dock', () {
        final r = NavVoice.match(phrase, points);
        expect(r.isCommand, isTrue, reason: phrase);
        expect(r.isDock, isTrue, reason: phrase);
        expect(r.point, isNull, reason: phrase);
      });
    }

    test('a question about the dock is NOT a drive command', () {
      final r = NavVoice.match('where is the charging station', points);
      expect(r.isDock, isFalse);
    });
  });

  group('NavVoice point / passthrough (regression)', () {
    test('matches a saved point, not dock', () {
      final r = NavVoice.match('take me to nishant desk', points);
      expect(r.isCommand, isTrue);
      expect(r.isDock, isFalse);
      expect(r.point?.name, 'Nishant Desk');
    });

    test('unknown place is a command with no point', () {
      final r = NavVoice.match('go to the moon', points);
      expect(r.isCommand, isTrue);
      expect(r.isDock, isFalse);
      expect(r.point, isNull);
    });

    test('chit-chat is not a command', () {
      final r = NavVoice.match('what time do you close', points);
      expect(r.isCommand, isFalse);
    });
  });

  group('NavVoice staff-desk navigation (meet a staff member)', () {
    // Staff desks arrive as nav points named after the person (spine
    // staff-desks.ts), so navigating to a colleague uses the same matcher.
    final staff = [_pt('Nishant'), _pt('Narasimha'), _pt('Reception')];

    test('"take me to Nishant" → Nishant\'s desk', () {
      final r = NavVoice.match('take me to Nishant', staff);
      expect(r.point?.name, 'Nishant');
    });

    test('"go to Nishant\'s desk" → Nishant (possessive + "desk" tolerated)', () {
      final r = NavVoice.match("go to Nishant's desk", staff);
      expect(r.point?.name, 'Nishant');
    });

    test('"navigate to Narasimha" → Narasimha\'s desk', () {
      final r = NavVoice.match('navigate to Narasimha', staff);
      expect(r.point?.name, 'Narasimha');
    });

    test('an unknown colleague is a command with no point (robot says so)', () {
      final r = NavVoice.match('take me to Priyanka', staff);
      expect(r.isCommand, isTrue);
      expect(r.point, isNull);
      expect(r.heard, 'Priyanka'); // case preserved — spoken verbatim in the reply
    });
  });
}
