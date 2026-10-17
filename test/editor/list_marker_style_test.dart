import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const blue = Color(0xFF2457C5);
  const red = Color(0xFFC62828);
  const green = Color(0xFF16833B);
  const orange = Color(0xFFF57C00);
  const customMarkerKey = 'marker-appearance';

  DefaultStyles listStyles({required double size, required Color color}) {
    return DefaultStyles(
      lists: DefaultListBlockStyle(
        TextStyle(fontSize: size, color: color),
        HorizontalSpacing.zero,
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        null,
        null,
      ),
    );
  }

  Document listDocument(
    String listType, {
    Map<String, dynamic>? inlineAttributes,
    bool includeEmptyLine = false,
    int? indent,
  }) {
    final lineAttributes = <String, dynamic>{'list': listType};
    if (indent != null) {
      lineAttributes['indent'] = indent;
    }
    final delta = Delta()
      ..insert('item', inlineAttributes)
      ..insert('\n', lineAttributes);
    if (includeEmptyLine) {
      delta.insert('\n', lineAttributes);
    }
    return Document.fromDelta(delta);
  }

  Future<List<LeadingConfig>> pumpList(
    WidgetTester tester, {
    required QuillController controller,
    DefaultStyles? customStyles,
    TextStyle Function(Attribute)? customStyleBuilder,
  }) async {
    final leadingConfigs = <LeadingConfig>[];
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
            config: QuillEditorConfig(
              customStyles: customStyles,
              customStyleBuilder: customStyleBuilder,
              customLeadingBlockBuilder: (node, config) {
                leadingConfigs.add(config);
                return null;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return leadingConfigs;
  }

  for (final listType in <String>[Attribute.ul.value!, Attribute.ol.value!]) {
    final label = listType == Attribute.ul.value ? 'bullet' : 'numbered';

    testWidgets('$label marker preserves ordinary list base metrics', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(listType),
        selection: const TextSelection.collapsed(offset: 0),
      );

      final configs = await pumpList(tester, controller: controller);

      expect(configs.last.style!.fontSize, 16);
      expect(configs.last.width, 32);
      expect(configs.last.padding, 8);
    });

    testWidgets('$label marker uses the effective custom list base style', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(listType),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final before = controller.document.toDelta().toJson();

      final configs = await pumpList(
        tester,
        controller: controller,
        customStyles: listStyles(size: 19, color: blue),
      );

      expect(configs.last.style!.fontSize, 19);
      expect(configs.last.style!.color, blue);
      expect(configs.last.width, 38);
      expect(configs.last.padding, 9.5);
      expect(controller.document.toDelta().toJson(), before);
    });

    testWidgets('$label marker uses first-run size, color, and metrics', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(
          listType,
          inlineAttributes: const <String, dynamic>{
            'size': '24',
            'color': '#c62828',
            'bold': true,
            'font': 'serif',
            'underline': true,
            'background': '#ffffff',
            'link': 'https://example.invalid',
          },
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );

      final configs = await pumpList(tester, controller: controller);
      final config = configs.last;

      expect(config.style!.fontSize, 24);
      expect(config.style!.color, red);
      expect(config.style!.fontWeight, FontWeight.bold);
      expect(config.style!.fontFamily, 'serif');
      expect(config.style!.decoration, TextDecoration.none);
      expect(config.style!.backgroundColor, isNull);
      expect(config.width, 48);
      expect(config.padding, 12);

      final markerFinder = listType == Attribute.ul.value
          ? find.byType(QuillBulletPoint)
          : find.byType(QuillNumberPoint);
      final bodyFinder = find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == 'item',
      );
      expect(tester.getSize(markerFinder).width, 48);
      expect(
        tester.getTopLeft(markerFinder).dy,
        closeTo(tester.getTopLeft(bodyFinder).dy, 0.01),
      );
    });

    testWidgets('$label marker supports smaller first-run typography', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(
          listType,
          inlineAttributes: const <String, dynamic>{'size': '10'},
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );

      final configs = await pumpList(tester, controller: controller);

      expect(configs.last.style!.fontSize, 10);
      expect(configs.last.width, 20);
      expect(configs.last.padding, 5);
    });

    testWidgets('$label marker applies safe customStyleBuilder typography', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(
          listType,
          inlineAttributes: const <String, dynamic>{
            customMarkerKey: true,
            'link': 'https://example.invalid',
          },
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );

      final configs = await pumpList(
        tester,
        controller: controller,
        customStyleBuilder: (attribute) {
          if (attribute.key == customMarkerKey) {
            return const TextStyle(
              fontSize: 21,
              color: green,
              backgroundColor: Colors.purple,
              decoration: TextDecoration.lineThrough,
            );
          }
          if (attribute.key == Attribute.link.key) {
            return const TextStyle(fontSize: 40, color: Colors.purple);
          }
          return const TextStyle();
        },
      );
      final config = configs.last;

      expect(config.style!.fontSize, 21);
      expect(config.style!.color, green);
      expect(config.style!.backgroundColor, isNull);
      expect(config.style!.decoration, TextDecoration.none);
      expect(config.width, 42);
      expect(config.padding, 10.5);
    });

    testWidgets('$label empty active list line uses insertion typography', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(
          listType,
          inlineAttributes: const <String, dynamic>{
            'size': '12',
            'color': '#2457c5',
          },
          includeEmptyLine: true,
          indent: 1,
        ),
        selection: const TextSelection.collapsed(offset: 5),
      )..forceToggledStyle(
          const Style.attr(<String, Attribute>{
            'size': SizeAttribute('26'),
            'color': ColorAttribute('#f57c00'),
          }),
        );
      final before = controller.document.toDelta().toJson();

      final configs = await pumpList(tester, controller: controller);
      final emptyLineConfig = configs.last;

      expect(emptyLineConfig.style!.fontSize, 26);
      expect(emptyLineConfig.style!.color, orange);
      expect(emptyLineConfig.width, 52);
      expect(emptyLineConfig.padding, 13);
      expect(emptyLineConfig.attrs[Attribute.list.key]!.value, listType);
      expect(emptyLineConfig.attrs[Attribute.indent.key]!.value, 1);
      expect(controller.document.toDelta().toJson(), before);
    });
  }

  testWidgets('checkbox leading remains on its existing rendering path', (
    tester,
  ) async {
    final controller = QuillController(
      document: listDocument(Attribute.unchecked.value!),
      selection: const TextSelection.collapsed(offset: 0),
    );

    final configs = await pumpList(
      tester,
      controller: controller,
      customStyles: listStyles(size: 19, color: blue),
    );

    expect(configs.last.style, isNull);
    expect(configs.last.lineSize, 16);
    expect(find.byType(QuillCheckboxPoint), findsOneWidget);
  });
}
