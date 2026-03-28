// Widget smoke tests for the Veea Context Capture app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veea_context_capture/main.dart';

void main() {
  testWidgets('VeeaContextApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const VeeaContextApp());
    // App should render a MaterialApp with the correct title.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('DashboardScreen shows header text', (WidgetTester tester) async {
    await tester.pumpWidget(const VeeaContextApp());
    // Allow async initState calls to settle.
    await tester.pump();
    expect(find.text('Veea Edge AI'), findsOneWidget);
    expect(find.text('Live Context Bridge'), findsOneWidget);
  });

  testWidgets('DashboardScreen shows empty state when no snapshots', (WidgetTester tester) async {
    await tester.pumpWidget(const VeeaContextApp());
    await tester.pump();
    // With no shared directory available in tests, the gallery is empty.
    expect(find.text('No Context Available'), findsOneWidget);
  });
}
