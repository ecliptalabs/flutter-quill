import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_quill_test/flutter_quill_test.dart';
import 'package:flutter_test/flutter_test.dart';

const _tolerance = 0.5;
const _largeAttributes = <String, dynamic>{
  'font': 'serif',
  'size': '43',
  'bold': true,
  'italic': true,
};

Future<void> _pump(
  WidgetTester tester,
  QuillController controller, {
  QuillFinalTextStyleResolver? resolver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QuillEditor.basic(
          controller: controller,
          config: QuillEditorConfig(
            padding: EdgeInsets.zero,
            finalTextStyleResolver: resolver,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _height(WidgetTester tester, int line) =>
    tester.getRect(find.byType(EditableTextLine).at(line)).height;

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Document _largeDocument() => Document.fromDelta(
  Delta()
    ..insert('Inter', _largeAttributes)
    ..insert('\n'),
);

void _expectLargeStyle(Style style) {
  expect(style.attributes[Attribute.font.key], const FontAttribute('serif'));
  expect(style.attributes[Attribute.size.key], const SizeAttribute('43'));
  expect(style.attributes[Attribute.bold.key], Attribute.bold);
  expect(style.attributes[Attribute.italic.key], Attribute.italic);
}

void main() {
  testWidgets(
    'Enter-created inherited empty line stays stable active inactive active',
    (tester) async {
      final controller = QuillController(
        document: _largeDocument(),
        selection: const TextSelection.collapsed(offset: 5),
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await tester.quillEnterTextAtPosition(find.byType(QuillEditor), '\n', 5);
      await tester.pump();

      const emptyOffset = 6;
      final delta = controller.document.toDelta().toJson();
      final activeStyle = controller.document.collectStyle(emptyOffset, 0);
      final activeHeight = _height(tester, 1);
      final activeCaret = tester
          .state<QuillRawEditorState>(find.byType(QuillRawEditor))
          .renderEditor
          .getLocalRectForCaret(const TextPosition(offset: emptyOffset));
      final undo = List<Delta>.of(controller.document.history.stack.undo);
      final redo = List<Delta>.of(controller.document.history.stack.redo);

      expect(delta, [
        {'insert': 'Inter', 'attributes': _largeAttributes},
        {'insert': '\n\n'},
      ]);
      _expectLargeStyle(activeStyle);
      _expectLargeStyle(controller.toggledStyle);
      expect(activeHeight, closeTo(49, _tolerance));

      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await tester.pump();
      final inactiveStyle = controller.document.collectStyle(emptyOffset, 0);
      final inactiveHeight = _height(tester, 1);

      controller.updateSelection(
        const TextSelection.collapsed(offset: emptyOffset),
        ChangeSource.local,
      );
      await tester.pump();
      final returnedHeight = _height(tester, 1);
      final returnedCaret = tester
          .state<QuillRawEditorState>(find.byType(QuillRawEditor))
          .renderEditor
          .getLocalRectForCaret(const TextPosition(offset: emptyOffset));

      expect(inactiveStyle, activeStyle);
      expect(inactiveHeight, closeTo(activeHeight, _tolerance));
      expect(returnedHeight, closeTo(activeHeight, _tolerance));
      expect(returnedCaret, activeCaret);
      expect(controller.document.toDelta().toJson(), delta);
      expect(controller.document.history.stack.undo, undo);
      expect(controller.document.history.stack.redo, redo);

      controller.document.history.cutoff();
      controller.replaceText(
        emptyOffset,
        0,
        'x',
        const TextSelection.collapsed(offset: emptyOffset + 1),
      );
      await tester.pump();
      final typedDelta = controller.document.toDelta().toJson();
      _expectLargeStyle(controller.document.collectStyle(emptyOffset, 1));
      controller.undo();
      await tester.pump();
      expect(controller.document.toDelta().toJson(), delta);
      controller.redo();
      await tester.pump();
      expect(controller.document.toDelta().toJson(), typedDelta);
      await _finish(tester);
    },
  );

  testWidgets('serialized Delta reconstructs inherited inactive geometry', (
    tester,
  ) async {
    final source = QuillController(
      document: _largeDocument(),
      selection: const TextSelection.collapsed(offset: 5),
    )..replaceText(5, 0, '\n', const TextSelection.collapsed(offset: 6));
    final serialized = source.document.toDelta().toJson();
    source.dispose();

    final controller = QuillController(
      document: Document.fromJson(serialized),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    final inactiveHeight = _height(tester, 1);
    _expectLargeStyle(controller.document.collectStyle(6, 0));

    controller.updateSelection(
      const TextSelection.collapsed(offset: 6),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(inactiveHeight, _tolerance));
    expect(inactiveHeight, closeTo(49, _tolerance));
    expect(controller.document.toDelta().toJson(), serialized);
    expect(controller.document.history.stack.undo, isEmpty);
    expect(controller.document.history.stack.redo, isEmpty);
    await _finish(tester);
  });

  testWidgets('consecutive inherited empty lines keep stable geometry', (
    tester,
  ) async {
    final controller = QuillController(
      document: _largeDocument(),
      selection: const TextSelection.collapsed(offset: 5),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.quillEnterTextAtPosition(find.byType(QuillEditor), '\n', 5);
    await tester.quillEnterTextAtPosition(find.byType(QuillEditor), '\n', 6);
    await tester.pump();

    final firstHeight = _height(tester, 1);
    final secondHeight = _height(tester, 2);
    _expectLargeStyle(controller.document.collectStyle(6, 0));
    _expectLargeStyle(controller.document.collectStyle(7, 0));
    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pump();

    expect(_height(tester, 1), closeTo(firstHeight, _tolerance));
    expect(_height(tester, 2), closeTo(secondHeight, _tolerance));
    expect(controller.document.toDelta().toJson(), [
      {'insert': 'Inter', 'attributes': _largeAttributes},
      {'insert': '\n\n\n'},
    ]);
    await _finish(tester);
  });

  testWidgets('normal and differently styled neighbors do not leak forward', (
    tester,
  ) async {
    final normal = QuillController(
      document: Document.fromDelta(Delta()..insert('normal\n\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(normal.dispose);
    await _pump(tester, normal);
    final normalInactive = _height(tester, 1);
    expect(normal.document.collectStyle(7, 0), const Style());
    normal.updateSelection(
      const TextSelection.collapsed(offset: 7),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(normalInactive, _tolerance));

    final largeThenNormal = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('large', _largeAttributes)
          ..insert('\n\nnormal\n'),
      ),
      selection: const TextSelection.collapsed(offset: 8),
    );
    addTearDown(largeThenNormal.dispose);
    await _pump(tester, largeThenNormal);
    final largeInactive = _height(tester, 1);
    _expectLargeStyle(largeThenNormal.document.collectStyle(6, 0));
    largeThenNormal.updateSelection(
      const TextSelection.collapsed(offset: 6),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(largeInactive, _tolerance));
    expect(largeInactive, greaterThan(_height(tester, 2) + 10));

    final different = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('left', {'size': '31', 'bold': true})
          ..insert('\n\n')
          ..insert('right', {'size': '18', 'italic': true})
          ..insert('\n'),
      ),
      selection: const TextSelection.collapsed(offset: 7),
    );
    addTearDown(different.dispose);
    await _pump(tester, different);
    final middleStyle = different.document.collectStyle(5, 0);
    final middleInactive = _height(tester, 1);
    expect(
      middleStyle.attributes[Attribute.size.key],
      const SizeAttribute('31'),
    );
    expect(middleStyle.attributes[Attribute.bold.key], Attribute.bold);
    expect(middleStyle.containsKey(Attribute.italic.key), isFalse);
    different.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(middleInactive, _tolerance));
    await _finish(tester);
  });

  testWidgets('manual toggled style remains active-only and does not leak', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('plain\n\n\n')),
      selection: const TextSelection.collapsed(offset: 6),
    )..forceToggledStyle(const Style.attr({'size': SizeAttribute('43')}));
    addTearDown(controller.dispose);
    final delta = controller.document.toDelta().toJson();
    await _pump(tester, controller);
    final activeManual = _height(tester, 1);
    final unrelated = _height(tester, 2);
    expect(activeManual, greaterThan(unrelated + 10));

    controller.updateSelection(
      const TextSelection.collapsed(offset: 7),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(_height(tester, 2), _tolerance));
    expect(controller.document.collectStyle(6, 0), const Style());
    expect(controller.document.collectStyle(7, 0), const Style());
    expect(controller.document.toDelta().toJson(), delta);
    await _finish(tester);
  });

  testWidgets('final style resolver controls inactive empty-line metrics', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('lead', {'size': '30', 'bold': true})
          ..insert('\n\n')
          ..insert('tail\n'),
      ),
      selection: const TextSelection.collapsed(offset: 5),
    );
    addTearDown(controller.dispose);
    final roles = <QuillFinalTextStyleRole>[];
    await _pump(
      tester,
      controller,
      resolver: (context, style, attributes, role) {
        roles.add(role);
        return role == QuillFinalTextStyleRole.emptyLineCaret
            ? style.copyWith(fontFamily: 'serif', fontSize: 52, height: 1.1)
            : style;
      },
    );
    final activeHeight = _height(tester, 1);
    expect(roles, contains(QuillFinalTextStyleRole.emptyLineCaret));

    roles.clear();
    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pump();
    expect(roles, contains(QuillFinalTextStyleRole.emptyLineCaret));
    expect(_height(tester, 1), closeTo(activeHeight, _tolerance));
    expect(activeHeight, greaterThan(50));
    await _finish(tester);
  });

  testWidgets('list pending-format Enter remains stable and semantic-free', (
    tester,
  ) async {
    final controller =
        QuillController(
          document: Document.fromDelta(
            Delta()
              ..insert('item', {'size': '32', 'bold': true})
              ..insert('\n', {'list': Attribute.ul.value}),
          ),
          selection: const TextSelection.collapsed(offset: 4),
        )..forceToggledStyle(
          const Style.attr({
            'font': FontAttribute('serif'),
            'size': SizeAttribute('32'),
            'bold': Attribute.bold,
          }),
        );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.quillEnterTextAtPosition(find.byType(QuillEditor), '\n', 4);
    await tester.pump();
    final delta = controller.document.toDelta().toJson();
    final activeHeight = _height(tester, 1);
    expect(
      controller.toggledStyle.attributes[Attribute.size.key],
      const SizeAttribute('32'),
    );
    expect(
      controller.document.collectStyle(5, 0).attributes[Attribute.list.key],
      Attribute.ul,
    );

    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pump();
    expect(_height(tester, 1), closeTo(activeHeight, _tolerance));
    expect(controller.document.toDelta().toJson(), delta);
    expect(delta, [
      {
        'insert': 'item',
        'attributes': {'size': '32', 'bold': true},
      },
      {
        'insert': '\n\n',
        'attributes': {'list': Attribute.ul.value},
      },
    ]);
    await _finish(tester);
  });

  for (final entry in <({String label, Map<String, dynamic> block})>[
    (label: 'header', block: {'header': 2}),
    (label: 'Code', block: {'code-block': true}),
    (label: 'BlockQuote', block: {'blockquote': true}),
    (label: 'double-spaced paragraph', block: {'line-height': 2.0}),
  ]) {
    testWidgets('${entry.label} Enter keeps contextual empty-line geometry', (
      tester,
    ) async {
      final controller = QuillController(
        document: Document.fromDelta(
          Delta()
            ..insert('styled', {'size': '32', 'italic': true})
            ..insert('\n', entry.block),
        ),
        selection: const TextSelection.collapsed(offset: 6),
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await tester.quillEnterTextAtPosition(find.byType(QuillEditor), '\n', 6);
      await tester.pump();
      final delta = controller.document.toDelta().toJson();
      final activeHeight = _height(tester, 1);
      expect(
        controller.document.collectStyle(7, 0).attributes[Attribute.size.key],
        const SizeAttribute('32'),
      );

      controller.updateSelection(
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await tester.pump();
      expect(_height(tester, 1), closeTo(activeHeight, _tolerance));
      expect(controller.document.toDelta().toJson(), delta);
      await _finish(tester);
    });
  }
}
