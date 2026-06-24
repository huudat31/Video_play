import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dual_video_player/main.dart';

void main() {
  testWidgets('Home page smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title of the players are shown
    expect(find.text('Binocular Player'), findsOneWidget);
    expect(find.text('Dual Video Player'), findsOneWidget);
  });
}
