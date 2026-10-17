import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const blue = Color(0xFF2457C5);
  const epsilon = 0.01;

  Document listDocument(
    String listType,
    List<double> sizes, {
    List<int?>? indents,
  }) {
    final delta = Delta();
    for (var index = 0; index < sizes.length; index++) {
      final lineAttributes = <String, dynamic>{'list': listType};
      final indent = indents?[index];
      if (indent != null) {
        lineAttributes['indent'] = indent;
      }
      delta
        ..insert('row${index + 1}', {
          'size': '${sizes[index]}',
          'color': '#2457c5',
        })
        ..insert('\n', lineAttributes);
    }
    return Document.fromDelta(delta);
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    QuillController controller, {
    DefaultStyles? customStyles,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              config: QuillEditorConfig(customStyles: customStyles),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder bodyFinder(int number) => find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == 'row$number',
  );

  RenderParagraph markerParagraph(WidgetTester tester, Finder finder) =>
      tester.renderObject<RenderParagraph>(finder);

  for (final markerSize in <double>[10, 16, 32]) {
    testWidgets(
      'ordered gutter fits 1, 2, and 3 digit labels at size $markerSize',
      (tester) async {
        final controller = QuillController(
          document: listDocument(
            Attribute.ol.value!,
            List<double>.filled(123, markerSize),
          ),
          selection: const TextSelection.collapsed(offset: 0),
        );
        addTearDown(controller.dispose);
        await pumpEditor(tester, controller);

        final markers = find.byType(QuillNumberPoint);
        expect(markers, findsNWidgets(123));
        final markerWidth = tester.getSize(markers.first).width;
        final bodyStart = tester.getTopLeft(bodyFinder(1)).dx;

        for (final number in <int>[1, 9, 10, 11, 12, 15, 99, 100, 101, 123]) {
          final marker = markers.at(number - 1);
          final markerRect = tester.getRect(marker);
          final label = '$number.';
          final labelFinder = find.text(label);
          final labelRect = tester.getRect(labelFinder);
          final labelWidget = tester.widget<Text>(labelFinder);

          expect(labelWidget.maxLines, 1);
          expect(labelWidget.softWrap, isFalse);
          expect(
            markerParagraph(tester, labelFinder).didExceedMaxLines,
            isFalse,
          );
          expect(labelRect.left, greaterThanOrEqualTo(markerRect.left));
          expect(
            labelRect.right,
            lessThanOrEqualTo(markerRect.right + epsilon),
          );
          expect(
            labelRect.right,
            closeTo(tester.getRect(find.text('123.')).right, epsilon),
          );
          expect(tester.getSize(marker).width, closeTo(markerWidth, epsilon));
          expect(
            tester.getTopLeft(bodyFinder(number)).dx,
            closeTo(bodyStart, epsilon),
          );
        }
      },
    );
  }

  testWidgets('ordered gutter expands deterministically from 99 to 100', (
    tester,
  ) async {
    final controller = QuillController(
      document: listDocument(Attribute.ol.value!, List<double>.filled(99, 16)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final widthAt99 = tester.getSize(find.byType(QuillNumberPoint).first).width;
    final bodyStartAt99 = tester.getTopLeft(bodyFinder(1)).dx;

    final insertion = Delta()
      ..retain(controller.document.length - 1)
      ..insert('\n', {'list': Attribute.ol.value})
      ..insert('row100', {'size': '16.0', 'color': '#2457c5'});
    controller.compose(insertion, controller.selection, ChangeSource.local);
    await tester.pump();

    expect(find.byType(QuillNumberPoint), findsNWidgets(100));
    final widthAt100 = tester
        .getSize(find.byType(QuillNumberPoint).first)
        .width;
    final bodyStartAt100 = tester.getTopLeft(bodyFinder(1)).dx;
    expect(widthAt100, greaterThan(widthAt99));
    expect(bodyStartAt100, greaterThan(bodyStartAt99));
    expect(
      tester.getSize(find.byType(QuillNumberPoint).at(99)).width,
      closeTo(widthAt100, epsilon),
    );
    expect(
      markerParagraph(tester, find.text('100.')).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getRect(find.text('100.')).right,
      lessThanOrEqualTo(
        tester.getRect(find.byType(QuillNumberPoint).at(99)).right + epsilon,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ordered nesting retains normal indentation increments', (
    tester,
  ) async {
    final controller = QuillController(
      document: listDocument(
        Attribute.ol.value!,
        const <double>[16, 16, 16],
        indents: const <int?>[null, 1, 2],
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final bodyStarts = <double>[
      for (var index = 1; index <= 3; index++)
        tester.getTopLeft(bodyFinder(index)).dx,
    ];
    expect(bodyStarts[1] - bodyStarts[0], closeTo(16, epsilon));
    expect(bodyStarts[2] - bodyStarts[1], closeTo(16, epsilon));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('a.'), findsOneWidget);
    expect(find.text('i.'), findsOneWidget);
  });

  testWidgets('bullet anchor is stable across inline marker sizes', (
    tester,
  ) async {
    const sizes = <double>[12, 14, 18, 24, 28, 32];
    final controller = QuillController(
      document: listDocument(Attribute.ul.value!, sizes),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final markers = find.byType(QuillBulletPoint);
    final bullets = find.text('•');
    final anchor = tester.getCenter(bullets.first).dx;
    final bodyStart = tester.getTopLeft(bodyFinder(1)).dx;
    for (var index = 0; index < sizes.length; index++) {
      final bullet = bullets.at(index);
      final marker = markers.at(index);
      final bulletRect = tester.getRect(bullet);
      final markerRect = tester.getRect(marker);
      final bodyRect = tester.getRect(bodyFinder(index + 1));
      final bulletWidget = tester.widget<Text>(bullet);

      expect(tester.getCenter(bullet).dx, closeTo(anchor, epsilon));
      expect(
        tester.getTopLeft(bodyFinder(index + 1)).dx,
        closeTo(bodyStart, epsilon),
      );
      expect(bulletWidget.style!.fontSize, sizes[index]);
      expect(bulletWidget.style!.color, blue);
      expect(bulletWidget.maxLines, 1);
      expect(bulletWidget.softWrap, isFalse);
      expect(markerParagraph(tester, bullet).didExceedMaxLines, isFalse);
      expect(bulletRect.left, greaterThanOrEqualTo(markerRect.left));
      expect(bulletRect.right, lessThanOrEqualTo(markerRect.right + epsilon));
      expect(bulletRect.right, lessThanOrEqualTo(bodyRect.left + epsilon));
    }
  });

  testWidgets('nested bullet moves by the normal indent without anchor drift', (
    tester,
  ) async {
    final controller = QuillController(
      document: listDocument(
        Attribute.ul.value!,
        const <double>[32, 32],
        indents: const <int?>[null, 1],
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    await pumpEditor(tester, controller);

    final bullets = find.text('•');
    expect(
      tester.getCenter(bullets.at(1)).dx - tester.getCenter(bullets.at(0)).dx,
      closeTo(16, epsilon),
    );
    expect(
      tester.getTopLeft(bodyFinder(2)).dx - tester.getTopLeft(bodyFinder(1)).dx,
      closeTo(16, epsilon),
    );
  });

  testWidgets('RTL ordered and bullet markers preserve directional geometry', (
    tester,
  ) async {
    for (final listType in <String>[Attribute.ol.value!, Attribute.ul.value!]) {
      final controller = QuillController(
        document: listDocument(listType, const <double>[12, 16, 24, 32]),
        selection: const TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(tester, controller, textDirection: TextDirection.rtl);

      final labels = listType == Attribute.ol.value
          ? <String>['1.', '2.', '3.', '4.']
          : List<String>.filled(4, '•');
      final markerFinder = listType == Attribute.ol.value
          ? find.byType(QuillNumberPoint)
          : find.byType(QuillBulletPoint);
      final targetEdge = tester.getRect(find.text(labels.first).first).left;
      final bodyEnd = tester.getRect(bodyFinder(1)).right;
      for (var index = 0; index < labels.length; index++) {
        final labelFinder = find
            .text(labels[index])
            .at(listType == Attribute.ol.value ? 0 : index);
        final labelRect = tester.getRect(labelFinder);
        final markerRect = tester.getRect(markerFinder.at(index));
        final currentBodyEnd = tester.getRect(bodyFinder(index + 1)).right;
        expect(
          Directionality.of(tester.element(markerFinder.at(index))),
          TextDirection.rtl,
        );
        expect(labelRect.left, closeTo(targetEdge, epsilon));
        expect(currentBodyEnd, closeTo(bodyEnd, epsilon));
        expect(labelRect.left, greaterThanOrEqualTo(markerRect.left - epsilon));
        expect(labelRect.right, lessThanOrEqualTo(markerRect.right + epsilon));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    }
  });

  testWidgets('custom indent keeps its end spacing and measured lower bound', (
    tester,
  ) async {
    final controller = QuillController(
      document: listDocument(Attribute.ol.value!, List<double>.filled(123, 32)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    final customStyles = DefaultStyles(
      lists: DefaultListBlockStyle(
        const TextStyle(fontSize: 16),
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
        null,
        indentWidthBuilder: (_, __, ___, ____) =>
            const HorizontalSpacing(34, 7),
      ),
    );
    await pumpEditor(tester, controller, customStyles: customStyles);

    final lines = find.byType(EditableTextLine);
    final markerWidth = tester
        .getSize(find.byType(QuillNumberPoint).first)
        .width;
    for (final index in <int>[0, 9, 99, 122]) {
      final line = tester.widget<EditableTextLine>(lines.at(index));
      expect(
        line.horizontalSpacing.left,
        greaterThanOrEqualTo(markerWidth - epsilon),
      );
      expect(line.horizontalSpacing.right, 7);
    }
    expect(
      markerParagraph(tester, find.text('123.')).didExceedMaxLines,
      isFalse,
    );
  });
}
