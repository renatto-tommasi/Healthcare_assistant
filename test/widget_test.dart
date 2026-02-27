import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthcare_continuum_app/main.dart';

void main() {
  testWidgets('app renders root screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: HealthcareContinuumApp(),
      ),
    );
    expect(find.text('Care Continuum'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Clinician'), findsOneWidget);
  });
}
