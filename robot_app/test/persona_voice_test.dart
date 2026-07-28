import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/services/persona_voice.dart';

void main() {
  group('PersonaVoice rename', () {
    test('change your name to X', () {
      final r = PersonaVoice.match('Change your name to Rocky');
      expect(r.isCommand, isTrue);
      expect(r.kind, PersonaCommandKind.rename);
      expect(r.newName, 'Rocky');
    });

    test('change your name from A to B keeps B', () {
      final r = PersonaVoice.match('Please change your name from Minee to Rocky');
      expect(r.kind, PersonaCommandKind.rename);
      expect(r.newName, 'Rocky');
    });

    test('compound request keeps only the name before "and"', () {
      final r = PersonaVoice.match(
          'change your name to Rocky and change your voice to feel like rocky');
      expect(r.kind, PersonaCommandKind.rename);
      expect(r.newName, 'Rocky');
    });

    test('your name is now X / we will call you X', () {
      expect(PersonaVoice.match('Your name is now Minee').newName, 'Minee');
      expect(PersonaVoice.match('We will call you Jarvis').newName, 'Jarvis');
    });

    test('ordinary sentences are not rename commands', () {
      expect(PersonaVoice.match('what is your name').isCommand, isFalse);
      expect(PersonaVoice.match('take me to the reception').isCommand, isFalse);
    });
  });

  group('PersonaVoice voice change', () {
    test('change your voice to rocky → deep preset', () {
      final r = PersonaVoice.match('Change your voice to feel like rocky');
      expect(r.isCommand, isTrue);
      expect(r.kind, PersonaCommandKind.voice);
      expect(r.preset?.name, 'Rocky (deep)');
    });

    test('use a female voice → Rachel', () {
      final r = PersonaVoice.match('use a female voice');
      expect(r.kind, PersonaCommandKind.voice);
      expect(r.preset?.name, 'Rachel (calm)');
    });

    test('unknown persona → voiceUnknown with heard text', () {
      final r = PersonaVoice.match('change your voice to darth vader');
      expect(r.kind, PersonaCommandKind.voice);
      expect(r.preset, isNull);
      expect(r.heard, isNotEmpty);
    });
  });
}
