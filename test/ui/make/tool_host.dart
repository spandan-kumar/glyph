import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the Make tab: a page that opens [tool] on top of itself,
/// so leaving the tool pops it like the real back button does.
class ToolHost extends StatelessWidget {
  const ToolHost({super.key, required this.tool});

  final Widget Function() tool;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tool())),
            child: const Text('Open tool'),
          ),
        ),
      );
}

/// Opens the tool from a [ToolHost]. Fixed pumps: tool previews never settle.
Future<void> openTool(WidgetTester tester) async {
  await tester.tap(find.text('Open tool'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Leaves the tool with the app bar's back button.
Future<void> leaveTool(WidgetTester tester) async {
  await tester.pageBack();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}
