import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

class _Resolution {
  const _Resolution(this.style, this.attributes, this.role);

  final TextStyle style;
  final Style attributes;
  final QuillFinalTextStyleRole role;
}

void main() {
  const resolvedFamily = 'Resolver Test Family';

  Future<void> pumpEditor(
    WidgetTester tester, {
    required QuillController controller,
    QuillFinalTextStyleResolver? resolver,
    TextSpanBuilder textSpanBuilder = defaultSpanBuilder,
    LeadingBlockNodeBuilder? leadingBuilder,
    DefaultStyles? customStyles,
    TextDirection textDirection = TextDirection.ltr,
    FocusNode? focusNode,
    ScrollController? scrollController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: QuillEditor(
              controller: controller,
              focusNode: focusNode ?? FocusNode(),
              scrollController: scrollController ?? ScrollController(),
              config: QuillEditorConfig(
                finalTextStyleResolver: resolver,
                textSpanBuilder: textSpanBuilder,
                customLeadingBlockBuilder: leadingBuilder,
                customStyles: customStyles,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ordinary text receives the complete final style and context', (
    tester,
  ) async {
    final document = Document.fromDelta(
      Delta()
        ..insert('regular', <String, dynamic>{
          'font': 'Matrix Regular',
          'size': '23',
          'color': '#2457c5',
          'underline': true,
          'strike': true,
          'background': '#fff59d',
        })
        ..insert(' italic', <String, dynamic>{
          'font': 'Matrix Italic',
          'italic': true,
        })
        ..insert(' bold', <String, dynamic>{
          'font': 'Matrix Bold',
          'bold': true,
        })
        ..insert(' boldItalic', <String, dynamic>{
          'font': 'Matrix Bold Italic',
          'bold': true,
          'italic': true,
        })
        ..insert('\n')
        ..insert('heading', <String, dynamic>{'font': 'Matrix Heading'})
        ..insert('\n', <String, dynamic>{'header': 2})
        ..insert('quote', <String, dynamic>{
          'font': 'Matrix Quote',
          'bold': true,
          'italic': true,
        })
        ..insert('\n', <String, dynamic>{'blockquote': true})
        ..insert('code', <String, dynamic>{'font': 'Matrix Code'})
        ..insert('\n', <String, dynamic>{'code-block': true}),
    );
    final controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    final resolutions = <_Resolution>[];
    final renderedStyles = <String, TextStyle>{};

    TextStyle resolve(
      BuildContext context,
      TextStyle style,
      Style attributes,
      QuillFinalTextStyleRole role,
    ) {
      resolutions.add(_Resolution(style, attributes, role));
      final weight = style.fontWeight == FontWeight.bold ? 'Bold' : 'Regular';
      final slant = style.fontStyle == FontStyle.italic ? 'Italic' : 'Upright';
      return style.copyWith(fontFamily: '$resolvedFamily $weight $slant');
    }

    await pumpEditor(
      tester,
      controller: controller,
      resolver: resolve,
      customStyles: const DefaultStyles(
        paragraph: DefaultTextBlockStyle(
          TextStyle(
            fontSize: 16,
            height: 1.4,
            letterSpacing: 1.25,
            wordSpacing: 2.5,
          ),
          HorizontalSpacing.zero,
          VerticalSpacing.zero,
          VerticalSpacing.zero,
          null,
        ),
      ),
      textSpanBuilder: (context, node, offset, text, style, recognizer) {
        renderedStyles[text.trim()] = style!;
        return defaultSpanBuilder(
          context,
          node,
          offset,
          text,
          style,
          recognizer,
        );
      },
    );

    _Resolution byFont(String family) => resolutions.firstWhere(
      (resolution) =>
          resolution.attributes.attributes[Attribute.font.key]?.value == family,
    );

    final regular = byFont('Matrix Regular');
    expect(regular.role, QuillFinalTextStyleRole.text);
    expect(regular.style.fontFamily, 'Matrix Regular');
    expect(regular.style.fontSize, 23);
    expect(regular.style.color, const Color(0xFF2457C5));
    expect(regular.style.backgroundColor, const Color(0xFFFFF59D));
    expect(regular.style.height, 1.4);
    expect(regular.style.letterSpacing, 1.25);
    expect(regular.style.wordSpacing, 2.5);
    expect(
      regular.style.decoration,
      TextDecoration.combine(const <TextDecoration>[
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
    expect(regular.attributes.containsKey(Attribute.header.key), isFalse);

    expect(byFont('Matrix Italic').style.fontStyle, FontStyle.italic);
    expect(byFont('Matrix Italic').style.fontWeight, isNot(FontWeight.bold));
    expect(byFont('Matrix Bold').style.fontWeight, FontWeight.bold);
    expect(byFont('Matrix Bold').style.fontStyle, isNot(FontStyle.italic));
    expect(byFont('Matrix Bold Italic').style.fontWeight, FontWeight.bold);
    expect(byFont('Matrix Bold Italic').style.fontStyle, FontStyle.italic);

    final heading = byFont('Matrix Heading');
    expect(heading.attributes.containsKey(Attribute.header.key), isTrue);
    expect(heading.style.fontWeight, FontWeight.bold);

    final quote = byFont('Matrix Quote');
    expect(quote.attributes.containsKey(Attribute.blockQuote.key), isTrue);
    expect(quote.style.fontWeight, FontWeight.bold);
    expect(quote.style.fontStyle, FontStyle.italic);

    final code = byFont('Matrix Code');
    expect(code.attributes.containsKey(Attribute.codeBlock.key), isTrue);
    expect(code.style.fontFamily, 'Matrix Code');

    expect(renderedStyles['regular']!.fontFamily, contains('Regular Upright'));
    expect(renderedStyles['italic']!.fontFamily, contains('Regular Italic'));
    expect(renderedStyles['bold']!.fontFamily, contains('Bold Upright'));
    expect(renderedStyles['boldItalic']!.fontFamily, contains('Bold Italic'));
  });

  testWidgets('the callback return value is used as the final style', (
    tester,
  ) async {
    const finalStyle = TextStyle(
      fontFamily: 'Final Only Family',
      fontSize: 41,
      color: Colors.purple,
      letterSpacing: 3,
    );
    TextStyle? renderedStyle;
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('styled', <String, dynamic>{
            'bold': true,
            'underline': true,
            'color': '#2457c5',
          })
          ..insert('\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);

    await pumpEditor(
      tester,
      controller: controller,
      resolver: (context, style, attributes, role) => finalStyle,
      textSpanBuilder: (context, node, offset, text, style, recognizer) {
        renderedStyle = style;
        return defaultSpanBuilder(
          context,
          node,
          offset,
          text,
          style,
          recognizer,
        );
      },
    );

    expect(identical(renderedStyle, finalStyle), isTrue);
    expect(renderedStyle!.decoration, isNull);
    expect(renderedStyle!.fontWeight, isNull);
  });

  for (final script in <String>['super', 'sub']) {
    testWidgets('$script script resolves every weight/slant combination', (
      tester,
    ) async {
      final delta = Delta();
      for (final entry in <({String font, bool bold, bool italic})>[
        (font: '$script regular', bold: false, italic: false),
        (font: '$script italic', bold: false, italic: true),
        (font: '$script bold', bold: true, italic: false),
        (font: '$script bold italic', bold: true, italic: true),
      ]) {
        delta.insert('x', <String, dynamic>{
          'script': script,
          'font': entry.font,
          'size': '20',
          if (entry.bold) 'bold': true,
          if (entry.italic) 'italic': true,
        });
      }
      delta.insert('\n');
      final controller = QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      final resolutions = <_Resolution>[];

      await pumpEditor(
        tester,
        controller: controller,
        resolver: (context, style, attributes, role) {
          resolutions.add(_Resolution(style, attributes, role));
          return style.copyWith(fontFamily: resolvedFamily);
        },
      );

      final scriptResolutionsByFont = <String, _Resolution>{};
      for (final resolution in resolutions.where(
        (resolution) => resolution.role == QuillFinalTextStyleRole.script,
      )) {
        scriptResolutionsByFont[resolution
                .attributes
                .attributes[Attribute.font.key]!
                .value] =
            resolution;
      }
      final scriptResolutions = scriptResolutionsByFont.values.toList();
      expect(scriptResolutions, hasLength(4));
      for (final resolution in scriptResolutions) {
        expect(resolution.style.fontSize, 14);
        expect(
          resolution.attributes.attributes[Attribute.script.key]?.value,
          script,
        );
      }

      _Resolution byFont(String family) => scriptResolutions.firstWhere(
        (resolution) =>
            resolution.attributes.attributes[Attribute.font.key]?.value ==
            family,
      );
      expect(
        byFont('$script regular').style.fontStyle,
        isNot(FontStyle.italic),
      );
      expect(byFont('$script italic').style.fontStyle, FontStyle.italic);
      expect(
        byFont('$script bold').style.fontWeight!.value,
        greaterThan(byFont('$script regular').style.fontWeight!.value),
      );
      expect(byFont('$script bold italic').style.fontStyle, FontStyle.italic);
      expect(
        byFont('$script bold italic').style.fontWeight,
        byFont('$script bold').style.fontWeight,
      );

      final scriptText = tester.widgetList<Text>(find.text('x')).toList();
      expect(scriptText, hasLength(4));
      expect(
        scriptText.every(
          (widget) => widget.style!.fontFamily == resolvedFamily,
        ),
        isTrue,
      );
    });
  }

  for (final listValue in <String>['bullet', 'ordered']) {
    testWidgets('$listValue marker uses the resolved style for layout', (
      tester,
    ) async {
      final delta = Delta()
        ..insert('item', <String, dynamic>{
          'font': '$listValue marker input',
          'size': '28',
          'color': '#c62828',
          'bold': true,
          'italic': true,
        })
        ..insert('\n', <String, dynamic>{
          'list': listValue,
          'indent': 2,
          'direction': 'rtl',
        });
      final controller = QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      final resolutions = <_Resolution>[];
      final leadingConfigs = <LeadingConfig>[];

      await pumpEditor(
        tester,
        controller: controller,
        textDirection: TextDirection.rtl,
        resolver: (context, style, attributes, role) {
          resolutions.add(_Resolution(style, attributes, role));
          if (role != QuillFinalTextStyleRole.listMarker) {
            return style.copyWith(fontFamily: resolvedFamily);
          }
          return style.copyWith(fontFamily: resolvedFamily, letterSpacing: 8);
        },
        leadingBuilder: (node, config) {
          leadingConfigs.add(config);
          return null;
        },
      );

      final markerResolution = resolutions.lastWhere(
        (resolution) => resolution.role == QuillFinalTextStyleRole.listMarker,
      );
      final leading = leadingConfigs.last;
      expect(markerResolution.style.fontSize, 28);
      expect(markerResolution.style.color, const Color(0xFFC62828));
      expect(markerResolution.style.fontWeight, FontWeight.bold);
      expect(
        markerResolution.attributes.attributes[Attribute.font.key]?.value,
        '$listValue marker input',
      );
      expect(
        markerResolution.attributes.containsKey(Attribute.italic.key),
        true,
      );
      expect(
        markerResolution.attributes.containsKey(Attribute.indent.key),
        true,
      );
      expect(leading.style!.fontFamily, resolvedFamily);
      expect(leading.style!.letterSpacing, 8);
      expect(leading.width, greaterThanOrEqualTo(56));
      expect(leading.attrs[Attribute.direction.key]?.value, 'rtl');
    });
  }

  testWidgets(
    'active and inactive empty list markers expose effective styles',
    (tester) async {
      final lineAttributes = <String, dynamic>{'list': 'bullet'};
      final controller =
          QuillController(
            document: Document.fromDelta(
              Delta()
                ..insert('item', <String, dynamic>{
                  'font': 'Inherited Marker',
                  'size': '18',
                })
                ..insert('\n', lineAttributes)
                ..insert('\n\n', lineAttributes),
            ),
            selection: const TextSelection.collapsed(offset: 5),
          )..forceToggledStyle(
            const Style.attr(<String, Attribute>{
              'font': FontAttribute('Active Marker'),
              'size': SizeAttribute('30'),
              'bold': Attribute.bold,
              'italic': Attribute.italic,
            }),
          );
      addTearDown(controller.dispose);
      final markerResolutions = <_Resolution>[];
      final originalDelta = controller.document.toDelta().toJson();

      await pumpEditor(
        tester,
        controller: controller,
        resolver: (context, style, attributes, role) {
          if (role == QuillFinalTextStyleRole.listMarker) {
            markerResolutions.add(_Resolution(style, attributes, role));
          }
          return style.copyWith(fontFamily: resolvedFamily);
        },
      );

      expect(markerResolutions.length, greaterThanOrEqualTo(3));
      final active = markerResolutions.firstWhere(
        (resolution) =>
            resolution.attributes.attributes[Attribute.font.key]?.value ==
            'Active Marker',
      );
      expect(active.style.fontSize, 30);
      expect(active.attributes.containsKey(Attribute.bold.key), isTrue);
      expect(active.attributes.containsKey(Attribute.italic.key), isTrue);
      expect(
        markerResolutions.where(
          (resolution) =>
              resolution.attributes.attributes[Attribute.font.key]?.value ==
              'Inherited Marker',
        ),
        isNotEmpty,
      );
      expect(controller.document.toDelta().toJson(), originalDelta);
    },
  );

  testWidgets(
    'changing or removing the resolver rebuilds without state changes',
    (tester) async {
      final controller = QuillController(
        document: Document.fromDelta(Delta()..insert('dynamic\n')),
        selection: const TextSelection.collapsed(offset: 3),
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);
      final originalDelta = controller.document.toDelta().toJson();
      final originalSelection = controller.selection;
      final originalUndo = List<Delta>.of(
        controller.document.history.stack.undo,
      );
      final originalRedo = List<Delta>.of(
        controller.document.history.stack.redo,
      );
      final renderedFamilies = <String?>[];

      InlineSpan capture(
        BuildContext context,
        Node node,
        int offset,
        String text,
        TextStyle? style,
        GestureRecognizer? recognizer,
      ) {
        renderedFamilies.add(style?.fontFamily);
        return defaultSpanBuilder(
          context,
          node,
          offset,
          text,
          style,
          recognizer,
        );
      }

      QuillFinalTextStyleResolver resolver(String family) =>
          (context, style, attributes, role) =>
              style.copyWith(fontFamily: family);

      await pumpEditor(
        tester,
        controller: controller,
        textSpanBuilder: capture,
        focusNode: focusNode,
        scrollController: scrollController,
      );
      final nullFamily = renderedFamilies.last;
      await pumpEditor(
        tester,
        controller: controller,
        resolver: resolver('Resolver A'),
        textSpanBuilder: capture,
        focusNode: focusNode,
        scrollController: scrollController,
      );
      expect(renderedFamilies.last, 'Resolver A');
      await pumpEditor(
        tester,
        controller: controller,
        resolver: resolver('Resolver B'),
        textSpanBuilder: capture,
        focusNode: focusNode,
        scrollController: scrollController,
      );
      expect(renderedFamilies.last, 'Resolver B');
      await pumpEditor(
        tester,
        controller: controller,
        textSpanBuilder: capture,
        focusNode: focusNode,
        scrollController: scrollController,
      );
      expect(renderedFamilies.last, nullFamily);

      expect(controller.document.toDelta().toJson(), originalDelta);
      expect(controller.selection, originalSelection);
      expect(controller.document.history.stack.undo, originalUndo);
      expect(controller.document.history.stack.redo, originalRedo);
    },
  );

  testWidgets('resolver work stays linear in rendered styled runs', (
    tester,
  ) async {
    const runCount = 300;
    final delta = Delta();
    for (var index = 0; index < runCount; index++) {
      delta.insert('x', <String, dynamic>{
        'font': 'Input ${index.isEven ? 'Even' : 'Odd'}',
        if (index.isEven) 'bold': true,
        if (index % 3 == 0) 'italic': true,
      });
    }
    delta.insert('\n');
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    var calls = 0;

    await pumpEditor(
      tester,
      controller: controller,
      resolver: (context, style, attributes, role) {
        calls++;
        return style.copyWith(fontFamily: resolvedFamily);
      },
    );

    expect(calls, greaterThanOrEqualTo(runCount));
    expect(calls, lessThanOrEqualTo(runCount * 2));
  });
}
