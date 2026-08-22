// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cellen/main.dart';
import 'package:cellen/core/router/router.dart';

void main() {
  testWidgets('Cellen application shell builds', (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Cellen test shell')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        routerProvider.overrideWithValue(router),
      ],
      child: const CellenApp(),
    ));
    await tester.pump();
    expect(find.byType(CellenApp), findsOneWidget);
    expect(find.text('Cellen test shell'), findsOneWidget);
  });
}
