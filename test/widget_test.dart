import 'package:flutter_test/flutter_test.dart';

import 'package:poketracker/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PokeTrackerApp());
    // The app bar title should be present.
    expect(find.text('PokeTracker'), findsWidgets);
  });
}
