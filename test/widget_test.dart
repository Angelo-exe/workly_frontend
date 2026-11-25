import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workly_frontend/main.dart';

void main() {
  testWidgets('Workly company login screen renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AuthPage(register: false)),
    );

    expect(find.text('Accesso azienda'), findsOneWidget);
    expect(find.text('Accedi'), findsOneWidget);
  });
}
