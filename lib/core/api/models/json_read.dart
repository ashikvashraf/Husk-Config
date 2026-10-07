// Tolerant readers: Husk sends some numbers as strings ("rotation":"0") and
// may omit fields on older versions.

int? readInt(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? double.tryParse(s)?.toInt(),
      _ => null,
    };

double? readDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

bool? readBool(Object? v) => switch (v) {
      bool b => b,
      num n => n != 0,
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };

String? readString(Object? v) => switch (v) {
      null => null,
      String s => s,
      _ => v.toString(),
    };

Map<String, Object?> readMap(Object? v) => v is Map<String, Object?> ? v : const {};

DateTime? readEpochMs(Object? v) {
  final ms = readInt(v);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}
