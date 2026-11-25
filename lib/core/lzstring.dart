/// Port of `LZString.decompressFromBase64` (lz-string 1.4.4, MIT), which
/// InteractiveHtmlBom uses to embed `pcbdata` in ibom.html.
library;

const _keyStrBase64 =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

final Map<int, int> _base64Reverse = {
  for (var i = 0; i < _keyStrBase64.length; i++) _keyStrBase64.codeUnitAt(i): i,
};

/// Returns null when [input] is not valid lz-string data.
String? lzDecompressFromBase64(String input) {
  if (input.isEmpty) return null;
  return _decompress(
    input.length,
    32,
    (index) => _base64Reverse[input.codeUnitAt(index)] ?? 0,
  );
}

String? _decompress(int length, int resetValue, int Function(int) nextValue) {
  // Indexes 0..2 are the control codes; real entries start at 3.
  final dictionary = <String?>[null, null, null];
  var enlargeIn = 4;
  var numBits = 3;
  final result = StringBuffer();

  var val = nextValue(0);
  var position = resetValue;
  var index = 1;

  int readBits(int n) {
    var bits = 0;
    final maxPower = 1 << n;
    var power = 1;
    while (power != maxPower) {
      final resb = val & position;
      position >>= 1;
      if (position == 0) {
        position = resetValue;
        val = index < length ? nextValue(index) : 0;
        index++;
      }
      if (resb > 0) bits |= power;
      power <<= 1;
    }
    return bits;
  }

  String c;
  switch (readBits(2)) {
    case 0:
      c = String.fromCharCode(readBits(8));
    case 1:
      c = String.fromCharCode(readBits(16));
    default:
      return '';
  }
  dictionary.add(c);
  var w = c;
  result.write(c);

  while (true) {
    if (index > length) return '';

    var code = readBits(numBits);
    switch (code) {
      case 0:
        dictionary.add(String.fromCharCode(readBits(8)));
        code = dictionary.length - 1;
        enlargeIn--;
      case 1:
        dictionary.add(String.fromCharCode(readBits(16)));
        code = dictionary.length - 1;
        enlargeIn--;
      case 2:
        return result.toString();
    }

    if (enlargeIn == 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }

    final String entry;
    if (code < dictionary.length && dictionary[code] != null) {
      entry = dictionary[code]!;
    } else if (code == dictionary.length) {
      entry = w + w[0];
    } else {
      return null;
    }
    result.write(entry);

    dictionary.add(w + entry[0]);
    enlargeIn--;
    w = entry;

    if (enlargeIn == 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
  }
}
