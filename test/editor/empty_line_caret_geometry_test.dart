import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const geometryTolerance = 0.5;

  Future<void> pumpEditor(
    WidgetTester tester,
    QuillController controller, {
    QuillFinalTextStyleResolver? finalTextStyleResolver,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            config: QuillEditorConfig(
              padding: EdgeInsets.zero,
              finalTextStyleResolver: finalTextStyleResolver,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ({Rect caret, double lineHeight}) geometry(
    WidgetTester tester,
    int offset,
    int lineIndex,
  ) {
    final renderEditor = tester
        .state<QuillRawEditorState>(find.byType(QuillRawEditor))
        .renderEditor;
    final caret = renderEditor.getLocalRectForCaret(
      TextPosition(offset: offset),
    );
    final caretTopLeft = renderEditor.localToGlobal(caret.topLeft);
    final lineRect = tester.getRect(
      find.byType(EditableTextLine).at(lineIndex),
    );
    return (
      caret: caret.shift(caretTopLeft - caret.topLeft - lineRect.topLeft),
      lineHeight: lineRect.height,
    );
  }

  void expectStableGeometry(
    ({Rect caret, double lineHeight}) before,
    ({Rect caret, double lineHeight}) after, {
    bool checkLineHeight = true,
  }) {
    expect(after.caret.top, closeTo(before.caret.top, geometryTolerance));
    expect(after.caret.bottom, closeTo(before.caret.bottom, geometryTolerance));
    expect(after.caret.height, closeTo(before.caret.height, geometryTolerance));
    if (checkLineHeight) {
      expect(after.lineHeight, closeTo(before.lineHeight, geometryTolerance));
    }
  }

  Future<void> verifyTypeDeleteAndReturn(
    WidgetTester tester, {
    required Document document,
    required int emptyOffset,
    required int emptyLineIndex,
    required int awayOffset,
    Style pendingStyle = const Style(),
    bool checkLineHeight = true,
    QuillFinalTextStyleResolver? finalTextStyleResolver,
  }) async {
    final controller = QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: emptyOffset),
    )..forceToggledStyle(pendingStyle);
    addTearDown(controller.dispose);
    final originalDelta = controller.document.toDelta().toJson();

    await pumpEditor(
      tester,
      controller,
      finalTextStyleResolver: finalTextStyleResolver,
    );
    expect(controller.document.toDelta().toJson(), originalDelta);
    final empty = geometry(tester, emptyOffset, emptyLineIndex);

    controller.replaceText(
      emptyOffset,
      0,
      'x',
      TextSelection.collapsed(offset: emptyOffset + 1),
    );
    await tester.pump();
    final typed = geometry(tester, emptyOffset + 1, emptyLineIndex);
    expectStableGeometry(empty, typed, checkLineHeight: checkLineHeight);

    controller.replaceText(
      emptyOffset,
      1,
      '',
      TextSelection.collapsed(offset: emptyOffset),
    );
    await tester.pump();
    final restored = geometry(tester, emptyOffset, emptyLineIndex);
    expectStableGeometry(empty, restored, checkLineHeight: checkLineHeight);
    expect(controller.document.toDelta().toJson(), originalDelta);

    controller.updateSelection(
      TextSelection.collapsed(offset: awayOffset),
      ChangeSource.local,
    );
    await tester.pump();
    controller.updateSelection(
      TextSelection.collapsed(offset: emptyOffset),
      ChangeSource.local,
    );
    await tester.pump();
    final returned = geometry(tester, emptyOffset, emptyLineIndex);
    expectStableGeometry(empty, returned, checkLineHeight: checkLineHeight);
    expect(controller.document.toDelta().toJson(), originalDelta);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('ordinary empty paragraph caret geometry remains unchanged', (
    tester,
  ) async {
    await verifyTypeDeleteAndReturn(
      tester,
      document: Document.fromDelta(Delta()..insert('\ntail\n')),
      emptyOffset: 0,
      emptyLineIndex: 0,
      awayOffset: 1,
      checkLineHeight: false,
    );
  });

  testWidgets('large pending paragraph caret matches its first character', (
    tester,
  ) async {
    await verifyTypeDeleteAndReturn(
      tester,
      document: Document.fromDelta(
        Delta()
          ..insert('lead', {'size': '32'})
          ..insert('\n\n')
          ..insert('tail\n'),
      ),
      emptyOffset: 5,
      emptyLineIndex: 1,
      awayOffset: 0,
      pendingStyle: const Style.attr({'size': SizeAttribute('32')}),
    );
  });

  testWidgets('bold and color pending style does not disturb caret geometry', (
    tester,
  ) async {
    await verifyTypeDeleteAndReturn(
      tester,
      document: Document.fromDelta(Delta()..insert('\ntail\n')),
      emptyOffset: 0,
      emptyLineIndex: 0,
      awayOffset: 1,
      checkLineHeight: false,
      pendingStyle: const Style.attr({
        'bold': Attribute.bold,
        'color': ColorAttribute('#c62828'),
      }),
    );
  });

  for (final listType in <String>[Attribute.ul.value!, Attribute.ol.value!]) {
    final label = listType == Attribute.ul.value ? 'bullet' : 'numbered';

    testWidgets('large empty $label caret matches its first character', (
      tester,
    ) async {
      final lineAttributes = <String, dynamic>{'list': listType};
      await verifyTypeDeleteAndReturn(
        tester,
        document: Document.fromDelta(
          Delta()
            ..insert('item', {'size': '32', 'color': '#2457c5'})
            ..insert('\n', lineAttributes)
            ..insert('\n', lineAttributes),
        ),
        emptyOffset: 5,
        emptyLineIndex: 1,
        awayOffset: 0,
        pendingStyle: const Style.attr({
          'size': SizeAttribute('32'),
          'color': ColorAttribute('#2457c5'),
        }),
      );
    });
  }

  for (final entry in const <({String label, Style style})>[
    (label: 'regular', style: Style()),
    (
      label: 'italic',
      style: Style.attr(<String, Attribute>{'italic': Attribute.italic}),
    ),
    (
      label: 'bold',
      style: Style.attr(<String, Attribute>{'bold': Attribute.bold}),
    ),
    (
      label: 'bold italic',
      style: Style.attr(<String, Attribute>{
        'bold': Attribute.bold,
        'italic': Attribute.italic,
      }),
    ),
    (
      label: 'large bold italic',
      style: Style.attr(<String, Attribute>{
        'size': SizeAttribute('30'),
        'bold': Attribute.bold,
        'italic': Attribute.italic,
      }),
    ),
  ]) {
    testWidgets(
      'resolved ${entry.label} empty caret matches its first character',
      (tester) async {
        final roles = <QuillFinalTextStyleRole>[];
        await verifyTypeDeleteAndReturn(
          tester,
          document: Document.fromDelta(
            Delta()
              ..insert('lead', entry.style.toJson())
              ..insert('\n\n')
              ..insert('tail\n'),
          ),
          emptyOffset: 5,
          emptyLineIndex: 1,
          awayOffset: 0,
          pendingStyle: entry.style,
          checkLineHeight: entry.label == 'large bold italic',
          finalTextStyleResolver: (context, style, attributes, role) {
            roles.add(role);
            if (role == QuillFinalTextStyleRole.emptyLineCaret) {
              expect(style.fontSize, isNotNull);
              expect(style.height, isNotNull);
            }
            return style.copyWith(fontFamily: 'serif');
          },
        );
        expect(roles, contains(QuillFinalTextStyleRole.emptyLineCaret));
        expect(roles, contains(QuillFinalTextStyleRole.text));
      },
    );
  }
}
