import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuillController controller;
  late RenderEditor renderEditor;

  setUp(() {
    final text = List<String>.generate(20, (index) => 'line $index').join('\n');
    controller = QuillController(
      document: Document.fromDelta(Delta()..insert('$text\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(padding: EdgeInsets.zero),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    renderEditor = tester
        .state<QuillRawEditorState>(find.byType(QuillRawEditor))
        .renderEditor;
  }

  double viewportBetweenSelectionEndpoints(TextSelection selection) {
    final endpoints = renderEditor.getEndpointsForSelection(selection);
    return (endpoints.first.point.dy + endpoints.last.point.dy) / 2;
  }

  testWidgets('forward selection reveals its active end extent', (
    tester,
  ) async {
    await pumpEditor(tester);
    final selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.document.length - 2,
    );
    renderEditor.selection = selection;

    final offset = renderEditor.getOffsetToRevealCursor(
      viewportBetweenSelectionEndpoints(selection),
      0,
      0,
    );

    expect(offset, isNotNull);
    expect(offset, greaterThan(0));
  });

  testWidgets('reversed selection reveals its active start extent', (
    tester,
  ) async {
    await pumpEditor(tester);
    final selection = TextSelection(
      baseOffset: controller.document.length - 2,
      extentOffset: 0,
    );
    renderEditor.selection = selection;

    final offset = renderEditor.getOffsetToRevealCursor(
      viewportBetweenSelectionEndpoints(selection),
      0,
      0,
    );

    expect(offset, 0);
  });

  testWidgets('collapsed selection retains caret reveal behavior', (
    tester,
  ) async {
    await pumpEditor(tester);
    final selection = TextSelection.collapsed(
      offset: controller.document.length - 2,
    );
    renderEditor.selection = selection;

    final offset = renderEditor.getOffsetToRevealCursor(80, 0, 0);

    expect(offset, isNotNull);
    expect(offset, greaterThan(0));
  });

  testWidgets('drag selection keeps explicit first/last endpoint behavior', (
    tester,
  ) async {
    await pumpEditor(tester);
    final end = controller.document.length - 2;
    final first = DragTextSelection(
      baseOffset: 0,
      extentOffset: end,
      first: true,
    );
    final viewportHeight = viewportBetweenSelectionEndpoints(first);
    renderEditor.selection = first;
    expect(renderEditor.getOffsetToRevealCursor(viewportHeight, 0, 0), 0);

    renderEditor.selection = DragTextSelection(
      baseOffset: 0,
      extentOffset: end,
      first: false,
    );
    final lastOffset = renderEditor.getOffsetToRevealCursor(
      viewportHeight,
      0,
      0,
    );
    expect(lastOffset, isNotNull);
    expect(lastOffset, greaterThan(0));
  });
}
