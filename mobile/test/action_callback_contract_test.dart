import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production UI does not contain empty action callbacks', () {
    final emptyCallback = RegExp(
      r'(?:onPressed|onTap)\s*:\s*(?:\(\)\s*)?\{\s*\}',
      multiLine: true,
    );
    final violations = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in emptyCallback.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        violations.add('${file.path}:$line');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Every visible action must perform work or explain why it cannot.',
    );
  });

  test('legacy finance actions hand off to the authoritative Finreg workspace',
      () {
    final source = File(
      'lib/features/admin/finance/finance_dashboard_screen.dart',
    ).readAsStringSync();

    // A hand-off is a drill-down: the person must be able to come back to the
    // legacy invoice they generated, so it pushes and never resets the stack.
    expect(source, contains("context.push('/admin/finance/invoices')"));
    expect(source, isNot(contains('context.go(')));
  });
}
