/// A message written for the user in Arabic and English. Screens show the
/// one matching the app language (see friendlyError).
abstract interface class LocalizedMessage {
  String get ar;
  String get en;
}

/// A plain bilingual text, e.g. an import warning attached to a row.
class Bilingual implements LocalizedMessage {
  const Bilingual(this.ar, this.en);
  @override
  final String ar;
  @override
  final String en;

  @override
  String toString() => ar;
}

/// The Arabic text is also `message`, so logs and callers that only know
/// [FormatException] keep working.
class LocalizedFormatException extends FormatException implements LocalizedMessage {
  const LocalizedFormatException(super.message, this.en);
  @override
  String get ar => message;
  @override
  final String en;
}

class LocalizedStateError extends StateError implements LocalizedMessage {
  LocalizedStateError(super.message, this.en);
  @override
  String get ar => message;
  @override
  final String en;
}

class LocalizedArgumentError extends ArgumentError implements LocalizedMessage {
  LocalizedArgumentError(String super.message, this.en);
  @override
  String get ar => message as String;
  @override
  final String en;
}
