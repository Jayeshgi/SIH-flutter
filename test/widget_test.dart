import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart'; // Adjust if your project name differs

void main() {
  testWidgets('MainScreen renders correctly', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const MyApp());

    // Verify that MainScreen's AppBar title is present
    expect(find.text('INCOIS Hazard App'), findsOneWidget);

    // Verify that the HomeScreen is shown by default
    expect(find.text('Home Screen\n(Coming Soon)'), findsOneWidget);
  });
}
