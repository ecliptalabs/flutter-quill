import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuillController controller;
  late FocusNode focusNode;

  setUp(() {
    const line = 'abcdefghijklmno';
    controller = QuillController(
      document: Document()..insert(0, '${List.filled(5, line).join('\n')}\n'),
      selection: const TextSelection.collapsed(offset: 9),
    );
    focusNode = FocusNode();
  });

  Future<RenderEditor> pumpEditor(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      if (!kIsWeb) {
        focusNode.dispose();
      }
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 180,
            child: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode,
              config: const QuillEditorConfig(
                padding: EdgeInsets.zero,
                showCursor: false,
              ),
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    return tester
        .state<QuillRawEditorState>(find.byType(QuillRawEditor))
        .renderEditor;
  }

  Future<void> invokeVerticalKeyboardAction(
    WidgetTester tester, {
    required bool forward,
    required bool extend,
  }) async {
    Actions.invoke(
      tester.element(find.byType(EditableTextLine).first),
      ExtendSelectionVerticallyToAdjacentLineIntent(
        forward: forward,
        collapseSelection: !extend,
      ),
    );
    await tester.pump();
    if (kIsWeb) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  testWidgets(
    'moving to a new caret ends a down run before ordinary vertical movement',
    (tester) async {
      final renderEditor = await pumpEditor(tester);
      const firstCaret = 9;
      final firstDown = renderEditor
          .getTextPositionBelow(const TextPosition(offset: firstCaret))
          .offset;

      await invokeVerticalKeyboardAction(
        tester,
        forward: true,
        extend: true,
      );
      expect(
        controller.selection,
        TextSelection(baseOffset: firstCaret, extentOffset: firstDown),
      );
      const newCaret = 33;
      controller.updateSelection(
        const TextSelection.collapsed(offset: newCaret),
        ChangeSource.local,
      );
      await tester.pump();
      final expected = renderEditor
          .getTextPositionBelow(const TextPosition(offset: newCaret))
          .offset;

      await invokeVerticalKeyboardAction(
        tester,
        forward: true,
        extend: false,
      );

      expect(
        controller.selection,
        TextSelection.collapsed(offset: expected),
        reason: 'The second down movement must start from the new caret.',
      );
    },
  );

  testWidgets(
    'moving to a new caret ends an up run before a second shift selection',
    (tester) async {
      final renderEditor = await pumpEditor(tester);
      const firstCaret = 57;
      controller.updateSelection(
        const TextSelection.collapsed(offset: firstCaret),
        ChangeSource.local,
      );
      await tester.pump();
      final firstUp = renderEditor
          .getTextPositionAbove(const TextPosition(offset: firstCaret))
          .offset;

      await invokeVerticalKeyboardAction(
        tester,
        forward: false,
        extend: true,
      );
      expect(
        controller.selection,
        TextSelection(baseOffset: firstCaret, extentOffset: firstUp),
      );

      const newCaret = 17;
      controller.updateSelection(
        const TextSelection.collapsed(offset: newCaret),
        ChangeSource.local,
      );
      await tester.pump();
      final expected = renderEditor
          .getTextPositionAbove(const TextPosition(offset: newCaret))
          .offset;

      await invokeVerticalKeyboardAction(
        tester,
        forward: false,
        extend: true,
      );

      expect(
        controller.selection,
        TextSelection(baseOffset: newCaret, extentOffset: expected),
        reason: 'The second up selection must use the new caret as its base.',
      );
    },
  );
}
