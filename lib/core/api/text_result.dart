/// A plain-text reply from an accessibility/command endpoint: `OK …`, `NONE …`,
/// `ERR …` or a value. These arrive with HTTP 200 and are shown, not thrown.
class TextResult {
  const TextResult(this.raw);

  final String raw;

  String get text => raw.trim();
  bool get isOk => _startsWithWord('OK');
  bool get isNone => _startsWithWord('NONE');
  bool get isErr => _startsWithWord('ERR');

  bool _startsWithWord(String word) => text == word || text.startsWith('$word ');

  @override
  String toString() => text;
}
