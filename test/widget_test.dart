import 'package:apex_flutter_demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Apex SDK overview', (tester) async {
    await tester.pumpWidget(const ApexDemoApp());
    await tester.pump();

    expect(find.text('APEX SDK'), findsOneWidget);
    expect(find.text('Open ad lab'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
