import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/child_model.dart';

void main() {
  group('Child.fromJson', () {
    test('parses the full backend shape incl. merged memory', () {
      final c = Child.fromJson({
        'id': 'abc123',
        'name': 'Bé Vy',
        'gender': 'girl',
        'age': 5,
        'interests': ['Elsa', 'khủng long'],
        'created_at': '2026-06-23T12:00:00+00:00',
        'memory': {'summary': 'thích công chúa', 'updated_at': '2026-06-23T12:30:00+00:00'},
      });
      expect(c.id, 'abc123');
      expect(c.name, 'Bé Vy'); // VN diacritics intact
      expect(c.gender, ChildGender.girl);
      expect(c.age, 5);
      expect(c.interests, ['Elsa', 'khủng long']);
      expect(c.memorySummary, 'thích công chúa');
      expect(c.memoryUpdatedAt, '2026-06-23T12:30:00+00:00');
    });

    test('empty memory + unknown gender degrade gracefully', () {
      final c = Child.fromJson({
        'id': 'x',
        'name': 'Khách',
        'gender': '???',
        'age': 5,
        'interests': <dynamic>[],
        'memory': {'summary': '', 'updated_at': null},
      });
      expect(c.gender, ChildGender.neutral);
      expect(c.memorySummary, '');
      expect(c.memoryUpdatedAt, isNull);
    });

    test('toProfileJson omits memory + serializes gender as backend enum', () {
      const c = Child(id: 'x', name: 'Bo', gender: ChildGender.boy, age: 6, interests: ['xe']);
      final j = c.toProfileJson();
      expect(j, {'name': 'Bo', 'gender': 'boy', 'age': 6, 'interests': ['xe']});
      expect(j.containsKey('memory'), isFalse);
      expect(j.containsKey('id'), isFalse);
    });

    test('toProfileJson refuses to persist a neutral-gender child', () {
      // neutral is display-only (guest / malformed); backend rejects it (422).
      // We surface it as a clear local ArgumentError instead.
      const c = Child(id: 'x', name: 'Khách', gender: ChildGender.neutral, age: 5);
      expect(c.toProfileJson, throwsArgumentError);
    });
  });

  test('gender string round-trip', () {
    for (final g in ChildGender.values) {
      expect(genderFromString(genderToString(g)), g);
    }
    expect(genderFromString(null), ChildGender.neutral);
  });
}
