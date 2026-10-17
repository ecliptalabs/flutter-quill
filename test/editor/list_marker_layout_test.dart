import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Document listDocument(
    String listType, {
    required double markerSize,
    int emptyLines = 1,
    int? indent,
  }) {
    final lineAttributes = <String, dynamic>{'list': listType};
    if (indent != null) {
      lineAttributes['indent'] = indent;
    }
    return Document.fromDelta(
      Delta()
        ..insert('item', {'size': '$markerSize'})
        ..insert('\n', lineAttributes)
        ..insert('\n' * emptyLines, lineAttributes),
    );
  }

  DefaultStyles customIndentStyles({required double markerSize}) {
    return DefaultStyles(
      lists: DefaultListBlockStyle(
        TextStyle(fontSize: markerSize),
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
        null,
        indentWidthBuilder: (block, context, count, numberPointWidthBuilder) {
          final indent =
              block.style.attributes[Attribute.indent.key]?.value as int? ?? 0;
          return HorizontalSpacing(34 + indent * 10, 7);
        },
      ),
    );
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    required QuillController controller,
    DefaultStyles? customStyles,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            config: QuillEditorConfig(customStyles: customStyles),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder markerFinder(String listType) => listType == Attribute.ul.value
      ? find.byType(QuillBulletPoint)
      : find.byType(QuillNumberPoint);

  for (final listType in <String>[Attribute.ul.value!, Attribute.ol.value!]) {
    final label = listType == Attribute.ul.value ? 'bullet' : 'numbered';

    testWidgets(
      '$label empty marker remains vertically visible at every size',
      (tester) async {
        for (final markerSize in <double>[12, 14, 18, 24, 28, 32]) {
          final controller = QuillController(
            document: listDocument(listType, markerSize: markerSize),
            selection: const TextSelection.collapsed(offset: 0),
          );

          await pumpEditor(tester, controller: controller);

          final markerRect = tester.getRect(markerFinder(listType).last);
          final lineRect = tester.getRect(find.byType(EditableTextLine).last);
          expect(markerRect.top, greaterThanOrEqualTo(lineRect.top));
          expect(markerRect.bottom, lessThanOrEqualTo(lineRect.bottom + 0.01));
          expect(markerRect.height, greaterThanOrEqualTo(markerSize));
          expect(lineRect.height, greaterThanOrEqualTo(markerRect.height));
        }
      },
    );

    testWidgets(
      '$label large marker line stays stable through type and delete',
      (tester) async {
        final controller = QuillController(
          document: listDocument(listType, markerSize: 32),
          selection: const TextSelection.collapsed(offset: 5),
        );
        await pumpEditor(tester, controller: controller);

        final emptyHeight = tester
            .getSize(find.byType(EditableTextLine).last)
            .height;
        controller.replaceText(
          5,
          0,
          'x',
          const TextSelection.collapsed(offset: 6),
        );
        await tester.pump();
        final typedHeight = tester
            .getSize(find.byType(EditableTextLine).last)
            .height;

        controller.replaceText(
          5,
          1,
          '',
          const TextSelection.collapsed(offset: 5),
        );
        await tester.pump(const Duration(seconds: 1));
        final restoredHeight = tester
            .getSize(find.byType(EditableTextLine).last)
            .height;

        expect(typedHeight, closeTo(emptyHeight, 0.01));
        expect(restoredHeight, closeTo(emptyHeight, 0.01));
      },
    );

    testWidgets('$label ordinary list row height remains unchanged', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(listType, markerSize: 16),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(tester, controller: controller);

      final lines = find.byType(EditableTextLine);
      expect(
        tester.getSize(lines.at(1)).height,
        lessThanOrEqualTo(tester.getSize(lines.at(0)).height),
      );
    });

    testWidgets('$label custom indent expands only when marker requires it', (
      tester,
    ) async {
      final smallController = QuillController(
        document: listDocument(listType, markerSize: 10),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(
        tester,
        controller: smallController,
        customStyles: customIndentStyles(markerSize: 10),
      );
      expect(tester.getSize(markerFinder(listType).first).width, 34);

      final largeController = QuillController(
        document: listDocument(listType, markerSize: 32),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(
        tester,
        controller: largeController,
        customStyles: customIndentStyles(markerSize: 32),
      );
      expect(
        tester.getSize(markerFinder(listType).first).width,
        greaterThanOrEqualTo(64),
      );

      final nestedController = QuillController(
        document: listDocument(listType, markerSize: 10, indent: 2),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(
        tester,
        controller: nestedController,
        customStyles: customIndentStyles(markerSize: 10),
      );
      expect(tester.getSize(markerFinder(listType).first).width, 54);
    });
  }

  testWidgets('multi-digit number marker remains inside its leading box', (
    tester,
  ) async {
    final lineAttributes = <String, dynamic>{'list': Attribute.ol.value};
    final delta = Delta();
    for (var index = 0; index < 12; index++) {
      delta
        ..insert(index == 11 ? 'item' : 'x', {'size': '32'})
        ..insert('\n', lineAttributes);
    }
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    await pumpEditor(
      tester,
      controller: controller,
      customStyles: customIndentStyles(markerSize: 32),
    );

    final markerRect = tester.getRect(find.byType(QuillNumberPoint).last);
    final textRect = tester.getRect(find.text('12.'));
    expect(markerRect.width, greaterThanOrEqualTo(64));
    expect(textRect.left, greaterThanOrEqualTo(markerRect.left));
    expect(textRect.right, lessThanOrEqualTo(markerRect.right + 0.01));
  });
}
