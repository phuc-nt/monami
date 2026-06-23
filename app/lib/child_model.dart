// The app-side model of a child, mirroring the backend's stored child doc
// (see backend/child_store.py). One device owns several of these.
//
// Backend JSON shape (keys are snake_case, as the REST API returns them):
//   { "id": "...", "name": "...", "gender": "boy"|"girl",
//     "age": 5, "interests": ["..."], "created_at": "ISO8601"|null,
//     "memory": { "summary": "...", "updated_at": "ISO8601"|null } }
//
// `gender` may also be "neutral" for a guest/unspecified child; the UI maps it
// to a neutral face variant (phase 4). Keep this in lockstep with the backend
// schema — a drift here breaks every CRUD round-trip.

enum ChildGender { boy, girl, neutral }

ChildGender genderFromString(String? s) => switch (s) {
      'boy' => ChildGender.boy,
      'girl' => ChildGender.girl,
      _ => ChildGender.neutral,
    };

String genderToString(ChildGender g) => switch (g) {
      ChildGender.boy => 'boy',
      ChildGender.girl => 'girl',
      ChildGender.neutral => 'neutral',
    };

class Child {
  const Child({
    required this.id,
    required this.name,
    required this.gender,
    required this.age,
    this.interests = const [],
    this.createdAt,
    this.memorySummary = '',
    this.memoryUpdatedAt,
  });

  final String id;
  final String name;
  final ChildGender gender;
  final int age;
  final List<String> interests;
  final String? createdAt;

  /// The companion's remembered summary about this child ("" if none yet).
  final String memorySummary;
  final String? memoryUpdatedAt;

  factory Child.fromJson(Map<String, dynamic> json) {
    final memory = (json['memory'] as Map<String, dynamic>?) ?? const {};
    return Child(
      id: json['id'] as String,
      name: json['name'] as String,
      gender: genderFromString(json['gender'] as String?),
      age: (json['age'] as num).toInt(),
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      createdAt: json['created_at'] as String?,
      memorySummary: (memory['summary'] as String?)?.trim() ?? '',
      memoryUpdatedAt: memory['updated_at'] as String?,
    );
  }

  /// Body for create/update requests. Memory is managed via its own endpoints,
  /// so it is intentionally NOT included here.
  ///
  /// A REGISTERED child is always `boy` or `girl` (the create form requires it);
  /// `neutral` is display-only (guest / malformed data) and the backend rejects
  /// it (VALID_GENDERS = boy|girl). So we never write `neutral` — surfacing it as
  /// an [ArgumentError] here turns a would-be opaque 422 into a clear local error.
  Map<String, dynamic> toProfileJson() {
    if (gender == ChildGender.neutral) {
      throw ArgumentError(
        'cannot persist a child with neutral gender — pick boy or girl',
      );
    }
    return {
      'name': name,
      'gender': genderToString(gender),
      'age': age,
      'interests': interests,
    };
  }
}
