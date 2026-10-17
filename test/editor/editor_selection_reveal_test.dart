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

  Offset globalPointForPosition(int offset) {
    final caret = renderEditor.getLocalRectForCaret(
      TextPosition(offset: offset),
    );
    return renderEditor.localToGlobal(caret.center);
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

  testWidgets('downward pointer extension reveals its lower active endpoint', (
    tester,
  ) async {
    await pumpEditor(tester);
    const start = 1;
    final end = controller.document.length - 3;

    renderEditor
      ..handleDragStart(
        DragStartDetails(globalPosition: globalPointForPosition(start)),
      )
      ..extendSelection(
        globalPointForPosition(end),
        cause: SelectionChangedCause.drag,
      );
    await tester.pump();

    expect(controller.selection, isA<DragTextSelection>());
    expect((controller.selection as DragTextSelection).first, isFalse);
    final offset = renderEditor.getOffsetToRevealCursor(
      viewportBetweenSelectionEndpoints(controller.selection),
      0,
      0,
    );
    expect(offset, isNotNull);
    expect(offset, greaterThan(0));
    renderEditor.handleDragEnd(DragEndDetails());
  });

  testWidgets('upward pointer extension reveals its upper active endpoint', (
    tester,
  ) async {
    await pumpEditor(tester);
    final start = controller.document.length - 3;
    const end = 1;

    renderEditor
      ..handleDragStart(
        DragStartDetails(globalPosition: globalPointForPosition(start)),
      )
      ..extendSelection(
        globalPointForPosition(end),
        cause: SelectionChangedCause.drag,
      );
    await tester.pump();

    expect(controller.selection, isA<DragTextSelection>());
    expect((controller.selection as DragTextSelection).first, isTrue);
    expect(
      renderEditor.getOffsetToRevealCursor(
        viewportBetweenSelectionEndpoints(controller.selection),
        0,
        0,
      ),
      0,
    );
    renderEditor.handleDragEnd(DragEndDetails());
  });

  testWidgets('pointer reversal updates which endpoint is active', (
    tester,
  ) async {
    await pumpEditor(tester);
    final start = controller.document.length ~/ 2;
    final lower = controller.document.length - 3;
    const upper = 1;

    renderEditor
      ..handleDragStart(
        DragStartDetails(globalPosition: globalPointForPosition(start)),
      )
      ..extendSelection(
        globalPointForPosition(lower),
        cause: SelectionChangedCause.drag,
      );
    await tester.pump();
    expect((controller.selection as DragTextSelection).first, isFalse);

    renderEditor.extendSelection(
      globalPointForPosition(upper),
      cause: SelectionChangedCause.drag,
    );
    await tester.pump();
    expect((controller.selection as DragTextSelection).first, isTrue);
    renderEditor.handleDragEnd(DragEndDetails());
  });
}
