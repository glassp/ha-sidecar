import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps en.json and de.json in sync and makes sure every key the code uses exists.
Map<String, dynamic> _flatten(Map<String, dynamic> m, [String prefix = '']) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    final key = prefix.isEmpty ? k : '$prefix.$k';
    final isPlural = v is Map && v.keys.every((e) => const {'zero', 'one', 'two', 'few', 'many', 'other'}.contains(e));
    if (v is Map<String, dynamic> && !isPlural) {
      out.addAll(_flatten(v, key));
    } else {
      out[key] = v;
    }
  });
  return out;
}

Set<String> _placeholders(dynamic v) {
  final text = v is Map ? v.values.join(' ') : '$v';
  return RegExp(r'\{(\w*)\}').allMatches(text).map((m) => m.group(1)!).toSet();
}

void main() {
  final en = _flatten(jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>);
  final de = _flatten(jsonDecode(File('assets/translations/de.json').readAsStringSync()) as Map<String, dynamic>);

  test('German has exactly the English keys', () {
    expect(de.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'only in de');
    expect(en.keys.toSet().difference(de.keys.toSet()), isEmpty, reason: 'missing in de');
  });

  test('placeholders match between languages', () {
    for (final k in en.keys) {
      expect(_placeholders(de[k]), _placeholders(en[k]), reason: 'placeholders differ for $k');
    }
  });

  test('no empty translations', () {
    for (final e in [...en.entries, ...de.entries]) {
      expect('${e.value}'.trim(), isNotEmpty, reason: e.key);
    }
  });

  test('every key used in lib/ exists', () {
    final used = <String>{};
    final literal = RegExp(r"'([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (k.contains(r'$') || k.endsWith('.dart') || k.endsWith('.png') || k.startsWith('package.')) continue;
        used.add(k);
      }
    }
    expect(used.where((k) => !en.containsKey(k)), isEmpty);
  });

  test('every setting has title, description and keywords', () {
    final ids = en.keys.where((k) => k.startsWith('settings.')).map((k) => k.split('.')[1]).toSet()..remove('permission');
    for (final id in ids) {
      for (final part in ['title', 'desc', 'kw']) {
        expect(en.containsKey('settings.$id.$part'), isTrue, reason: 'settings.$id.$part');
      }
    }
  });
}
