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
      expect(configs.last.width, greaterThanOrEqualTo(32));
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
      expect(configs.last.width, greaterThanOrEqualTo(38));
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
      expect(config.width, greaterThanOrEqualTo(48));
      expect(config.padding, 12);

      final markerFinder = listType == Attribute.ul.value
          ? find.byType(QuillBulletPoint)
          : find.byType(QuillNumberPoint);
      final bodyFinder = find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == 'item',
      );
      expect(tester.getSize(markerFinder).width, config.width);
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
      expect(configs.last.width, greaterThanOrEqualTo(20));
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
      expect(config.width, greaterThanOrEqualTo(42));
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
      expect(emptyLineConfig.width, greaterThanOrEqualTo(52));
      expect(emptyLineConfig.padding, 13);
      expect(emptyLineConfig.attrs[Attribute.list.key]!.value, listType);
      expect(emptyLineConfig.attrs[Attribute.indent.key]!.value, 1);
      expect(controller.document.toDelta().toJson(), before);
    });

    testWidgets('$label empty inactive marker inherits preceding typography', (
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
          },
          includeEmptyLine: true,
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final before = controller.document.toDelta().toJson();

      final configs = await pumpList(tester, controller: controller);
      final emptyLineConfig = configs.last;

      expect(emptyLineConfig.style!.fontSize, 24);
      expect(emptyLineConfig.style!.color, red);
      expect(emptyLineConfig.style!.fontWeight, FontWeight.bold);
      expect(emptyLineConfig.style!.fontFamily, 'serif');
      expect(controller.document.toDelta().toJson(), before);
    });

    testWidgets('$label backspace-to-empty marker inherits preceding style', (
      tester,
    ) async {
      final document = Document.fromDelta(Delta()
        ..insert('item', {
          'size': '24',
          'color': '#c62828',
          'font': 'serif',
        })
        ..insert('\n', {'list': listType})
        ..insert('next', {
          'size': '18',
          'color': '#2457c5',
        })
        ..insert('\n', {'list': listType}));
      final controller = QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 9),
      )..replaceText(5, 4, '', const TextSelection.collapsed(offset: 5));
      final beforeRender = controller.document.toDelta().toJson();

      final configs = await pumpList(tester, controller: controller);
      final emptyLineConfig = configs.last;

      expect(emptyLineConfig.style!.fontSize, 24);
      expect(emptyLineConfig.style!.color, red);
      expect(emptyLineConfig.style!.fontFamily, 'serif');
      expect(controller.document.toDelta().toJson(), beforeRender);
    });

    testWidgets('$label blank Enter continuation keeps inherited markers', (
      tester,
    ) async {
      final controller = QuillController(
        document: Document.fromDelta(Delta()
          ..insert('item', {
            'size': '24',
            'color': '#c62828',
            'bold': true,
          })
          ..insert('\n\n', {'list': listType})
          ..insert('tail')
          ..insert('\n', {'list': listType})),
        selection: const TextSelection.collapsed(offset: 5),
      )
        ..replaceText(5, 0, '\n', const TextSelection.collapsed(offset: 6))
        ..updateSelection(
            const TextSelection.collapsed(offset: 0), ChangeSource.local);
      final beforeRender = controller.document.toDelta().toJson();

      final configs = await pumpList(tester, controller: controller);
      final renderedConfigs = configs.sublist(configs.length - 4);

      for (final emptyLineConfig in renderedConfigs.sublist(1, 3)) {
        expect(emptyLineConfig.style!.fontSize, 24);
        expect(emptyLineConfig.style!.color, red);
        expect(emptyLineConfig.style!.fontWeight, FontWeight.bold);
      }
      expect(controller.document.toDelta().toJson(), beforeRender);
    });

    testWidgets('$label inherited customStyleBuilder typography wins', (
      tester,
    ) async {
      final controller = QuillController(
        document: listDocument(
          listType,
          inlineAttributes: const <String, dynamic>{'size': '18'},
          includeEmptyLine: true,
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final before = controller.document.toDelta().toJson();

      final configs = await pumpList(
        tester,
        controller: controller,
        customStyleBuilder: (attribute) =>
            attribute.key == Attribute.size.key
                ? const TextStyle(
                    fontSize: 29,
                    color: green,
                    fontFamily: 'monospace',
                  )
                : const TextStyle(),
      );
      final emptyLineConfig = configs.last;

      expect(emptyLineConfig.style!.fontSize, 29);
      expect(emptyLineConfig.style!.color, green);
      expect(emptyLineConfig.style!.fontFamily, 'monospace');
      expect(controller.document.toDelta().toJson(), before);
    });

    testWidgets('$label combined styled empty-list continuation stays stable', (
      tester,
    ) async {
      final controller = QuillController(
        document: Document.fromDelta(Delta()
          ..insert('item', {
            'size': '32',
            'color': '#c62828',
            'bold': true,
          })
          ..insert('\n', {'list': listType})
          ..insert('tail')
          ..insert('\n', {'list': listType})),
        selection: const TextSelection.collapsed(offset: 4),
      )..forceToggledStyle(const Style.attr({
          'size': SizeAttribute('32'),
          'color': ColorAttribute('#c62828'),
          'bold': Attribute.bold,
        }))
        ..replaceText(
            4, 0, '\n', const TextSelection.collapsed(offset: 5));
      final configs = await pumpList(tester, controller: controller);
      var current = configs.sublist(configs.length - 3);
      expect(current[1].style!.fontSize, 32);
      expect(current[1].style!.color, red);

      controller.replaceText(
          5, 0, '\n', const TextSelection.collapsed(offset: 6));
      await tester.pump();
      current = configs.sublist(configs.length - 4);
      for (final emptyLineConfig in current.sublist(1, 3)) {
        expect(emptyLineConfig.style!.fontSize, 32);
        expect(emptyLineConfig.style!.color, red);
      }

      controller.updateSelection(
          const TextSelection.collapsed(offset: 7), ChangeSource.local);
      await tester.pump();
      current = configs.sublist(configs.length - 4);
      for (final emptyLineConfig in current.sublist(1, 3)) {
        expect(emptyLineConfig.style!.fontSize, 32);
        expect(emptyLineConfig.style!.color, red);
      }

      controller
        ..replaceText(6, 0, 'x', const TextSelection.collapsed(offset: 7))
        ..replaceText(6, 1, '', const TextSelection.collapsed(offset: 6));
      await tester.pump(const Duration(seconds: 1));
      current = configs.sublist(configs.length - 4);
      expect(current[2].style!.fontSize, 32);
      expect(current[2].style!.color, red);
      expect(controller.document.toDelta().toJson(), [
        {
          'insert': 'item',
          'attributes': {'bold': true, 'size': '32', 'color': '#c62828'}
        },
        {'insert': '\n\n\n', 'attributes': {'list': listType}},
        {'insert': 'tail'},
        {
          'insert': '\n',
          'attributes': {'list': listType}
        }
      ]);
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
