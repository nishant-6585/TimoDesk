import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/services/checkin_voice.dart';
import 'package:robot_app/services/voice_fuzzy.dart';

void main() {
  group('CheckinVoice.match', () {
    test('matches "I\'m here to see <name>" variants (with/without apostrophe)',
        () {
      for (final t in [
        "I'm here to see Priya Sharma",
        'im here to meet Priya Sharma',
        'i am here to see priya sharma.',
        'Here to meet Priya Sharma',
      ]) {
        final r = CheckinVoice.match(t);
        expect(r.isCommand, isTrue, reason: t);
        expect(r.hostHeard.toLowerCase(), 'priya sharma', reason: t);
      }
    });

    test('matches meeting/appointment phrasing', () {
      expect(CheckinVoice.match('I have a meeting with Vishal').hostHeard,
          'Vishal');
      expect(CheckinVoice.match('appointment with Vishal?').hostHeard,
          'Vishal');
      expect(
          CheckinVoice.match('I want to see Nishant Kumar').hostHeard,
          'Nishant Kumar');
    });

    test('ignores unrelated speech', () {
      for (final t in [
        'what does xboom build',
        'go to reception',
        'see you later',
        'the meeting room is nice',
      ]) {
        expect(CheckinVoice.match(t).isCommand, isFalse, reason: t);
      }
    });
  });

  group('CheckinVoice.bestHost', () {
    const staff = [
      StaffMember(id: '1', fullName: 'Priya Sharma'),
      StaffMember(id: '2', fullName: 'Nishant Kumar'),
      StaffMember(id: '3', fullName: 'Vishal'),
    ];

    test('exact and partial names resolve', () {
      expect(CheckinVoice.bestHost('priya sharma', staff)?.id, '1');
      expect(CheckinVoice.bestHost('priya', staff)?.id, '1');
      expect(CheckinVoice.bestHost('mister nishant', staff)?.id, '2');
    });

    test('STT vowel swaps still resolve (edit distance 1)', () {
      expect(CheckinVoice.bestHost('prisha sharma', staff)?.id, '1');
    });

    test('unknown names return null instead of a wrong host', () {
      expect(CheckinVoice.bestHost('doctor strange', staff), isNull);
      expect(CheckinVoice.bestHost('', staff), isNull);
    });
  });

  group('CheckinVoice.extractVisitorName', () {
    test('strips lead-ins and title-cases', () {
      expect(CheckinVoice.extractVisitorName('my name is arun mehta'),
          'Arun Mehta');
      expect(CheckinVoice.extractVisitorName("I'm Arun"), 'Arun');
      expect(CheckinVoice.extractVisitorName('this is arun.'), 'Arun');
      expect(CheckinVoice.extractVisitorName('Arun Mehta'), 'Arun Mehta');
    });

    test('rejects empty/absurd input', () {
      expect(CheckinVoice.extractVisitorName('   '), '');
      expect(CheckinVoice.extractVisitorName('x' * 80), '');
    });
  });

  group('CheckinVoice.isCancel', () {
    test('recognises back-outs, passes names through', () {
      expect(CheckinVoice.isCancel('never mind'), isTrue);
      expect(CheckinVoice.isCancel('Cancel.'), isTrue);
      expect(CheckinVoice.isCancel('Arun Mehta'), isFalse);
    });
  });

  group('CheckinVoice.isSkip', () {
    test('recognises declining an optional detail', () {
      expect(CheckinVoice.isSkip('skip'), isTrue);
      expect(CheckinVoice.isSkip('Prefer not to say.'), isTrue);
      expect(CheckinVoice.isSkip('no thanks'), isTrue);
    });

    test('a real answer is not a skip', () {
      expect(CheckinVoice.isSkip('Wipro'), isFalse);
      expect(CheckinVoice.isSkip('quarterly business review'), isFalse);
    });

    test('"no" stays a CANCEL, not a skip', () {
      // isCancel is checked first in the dialog; keeping "no" out of isSkip
      // means a visitor saying "no" backs out rather than silently continuing.
      expect(CheckinVoice.isSkip('no'), isFalse);
      expect(CheckinVoice.isCancel('no'), isTrue);
    });
  });

  group('CheckinVoice.extractDetail', () {
    test('strips conversational lead-ins for company', () {
      expect(CheckinVoice.extractDetail("I'm from Wipro"), 'Wipro');
      expect(CheckinVoice.extractDetail('I work at Tata Steel'), 'Tata Steel');
      expect(CheckinVoice.extractDetail('from Reliance.'), 'Reliance');
      expect(CheckinVoice.extractDetail('The company is JSW'), 'JSW');
    });

    test('strips lead-ins for purpose', () {
      expect(CheckinVoice.extractDetail("It's about the SAP migration"),
          'the SAP migration');
      expect(CheckinVoice.extractDetail('here for the quarterly review'),
          'the quarterly review');
    });

    test('passes a bare answer through unchanged', () {
      expect(CheckinVoice.extractDetail('Mindsprint'), 'Mindsprint');
    });

    test('returns empty for nothing usable, so the caller stores null', () {
      expect(CheckinVoice.extractDetail('   '), '');
      expect(CheckinVoice.extractDetail('.'), '');
    });

    test('caps a runaway STT answer at the spine\'s 120-char limit', () {
      final long = CheckinVoice.extractDetail('a' * 400);
      expect(long.length, 120);
    });
  });

  group('voice_fuzzy (shared with NavVoice)', () {
    test('normalize strips possessives and punctuation', () {
      expect(fuzzyNormalize("Nishant's Desk!"), 'nishant desk');
    });

    test('score: equality > containment > token overlap', () {
      expect(fuzzyScore('reception', 'reception'), 1.0);
      expect(fuzzyScore('the reception area', 'reception'), 0.9);
      expect(fuzzyScore('nishant desk', 'nishant kumar desk'),
          closeTo(2 / 3, 0.001));
      expect(fuzzyScore('go to the moon', 'reception'), 0);
    });

    test('score: fused/split compound words match (STT word boundaries)', () {
      // STT hears "restroom" but the point is saved as "Rest Room" — the
      // space-squashed comparison must bridge the word boundary both ways.
      expect(fuzzyScore('restroom', 'rest room'), 0.9);
      expect(fuzzyScore('rest room', 'restroom'), 0.9);
      expect(fuzzyScore('restrom', 'rest room'), 0.85); // + one typo
      expect(fuzzyScore('kitchen', 'rest room'), 0); // no false positives
    });

    test('score: trivial fragments never containment-match', () {
      // Live incident 2026-07-27: STT garble left heard="the", which
      // containment-matched "The Dock Cabin" at 0.9 and DROVE THE ROBOT to
      // the wrong place. Stopword-only fragments must score ~0.
      expect(fuzzyScore('the', 'the dock cabin'), lessThan(0.5));
      expect(fuzzyScore('to the', 'the dock cabin'), lessThan(0.5));
      expect(fuzzyTrivial('the'), isTrue);
      expect(fuzzyTrivial('dock cabin'), isFalse);
      // Meaningful fragments still match.
      expect(fuzzyScore('dock cabin', 'the dock cabin'), 0.9);
    });
  });
}
