import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthcare_continuum_app/main.dart';

void main() {
  testWidgets('app renders role selection screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: HealthcareApp(),
      ),
    );
    expect(find.text('Role Selection'), findsOneWidget);
    expect(find.text('I am a Patient'), findsOneWidget);
    expect(find.text('I am a Clinician'), findsOneWidget);
  });
}
