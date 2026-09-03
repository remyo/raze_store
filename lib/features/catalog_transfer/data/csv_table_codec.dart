/// Small RFC 4180-style CSV codec kept local so catalog import does not depend
/// on a spreadsheet package at runtime.
final class CsvTableCodec {
  const CsvTableCodec();

  String encode(List<List<Object?>> rows) {
    return rows.map((row) => row.map(_escape).join(',')).join('\r\n');
  }

  List<List<String>> decode(String source) {
    final input = source.startsWith('\uFEFF') ? source.substring(1) : source;
    if (input.isEmpty) return const [];

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;

    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (quoted) {
        if (character == '"') {
          final hasEscapedQuote =
              index + 1 < input.length && input[index + 1] == '"';
          if (hasEscapedQuote) {
            field.write('"');
            index++;
          } else {
            quoted = false;
          }
        } else {
          field.write(character);
        }
        continue;
      }

      switch (character) {
        case '"':
          if (field.isNotEmpty) {
            throw const FormatException(
              'A quote must begin at the start of a CSV field.',
            );
          }
          quoted = true;
        case ',':
          row.add(field.toString());
          field.clear();
        case '\r':
          if (index + 1 < input.length && input[index + 1] == '\n') index++;
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = <String>[];
        case '\n':
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = <String>[];
        default:
          field.write(character);
      }
    }

    if (quoted) {
      throw const FormatException('The CSV ends inside a quoted field.');
    }
    if (field.isNotEmpty || row.isNotEmpty || input.endsWith(',')) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  String _escape(Object? value) {
    final text = value?.toString() ?? '';
    final needsQuotes =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\r') ||
        text.contains('\n') ||
        text.startsWith(' ') ||
        text.endsWith(' ');
    if (!needsQuotes) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}
