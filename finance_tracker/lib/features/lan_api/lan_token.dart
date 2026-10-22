/// In-memory LAN API token: crypto-random 6-char, regenerated every start.
///
/// Alphabet drops confusables (0/O, 1/I/L) so the owner can read it off
/// the phone screen and type it into a PC browser without mistakes.
/// Comparison is a plain `==` on a 6-char secret (per contract §5: fine).
library;

import 'dart:math';

/// 31 unambiguous chars: A-Z minus O/I/L, digits minus 0/1.
const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Generates one fresh 6-char token using [Random.secure].
String generateToken([Random? random]) {
  final rng = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buf.write(_alphabet[rng.nextInt(_alphabet.length)]);
  }
  return buf.toString();
}

/// Holds the current server token in memory only. Never persisted.
class LanToken {
  String _current = '';

  /// Issues a fresh token, invalidating the previous one.
  String rotate() {
    _current = generateToken();
    return _current;
  }

  String get current => _current;

  /// True only for the exact current token. Null/empty/wrong → false.
  bool validate(String? candidate) {
    if (candidate == null || candidate.isEmpty || _current.isEmpty) {
      return false;
    }
    return candidate == _current;
  }
}
