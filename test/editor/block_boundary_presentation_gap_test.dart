import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_block.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageColor = Color(0xff17324d);
const _codeColor = Color(0xfffafafa);
const _quoteBorderColor = Color(0xffe91e63);

const _decoratedStyles = DefaultStyles(
  code: DefaultTextBlockStyle(
    TextStyle(color: Colors.black, fontSize: 14, height: 1),
    HorizontalSpacing.zero,
    VerticalSpacing(7, 5),
    VerticalSpacing.zero,
    BoxDecoration(
      color: _codeColor,
      border: Border.fromBorderSide(BorderSide(color: Colors.black)),
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
  ),
  quote: DefaultTextBlockStyle(
    TextStyle(color: Colors.white, fontSize: 14, height: 1),
    HorizontalSpacing.zero,
    VerticalSpacing(6, 4),
    VerticalSpacing.zero,
    BoxDecoration(
      border: Border(left: BorderSide(width: 4, color: _quoteBorderColor)),
    ),
  ),
);

class _EditorHarness {
  _EditorHarness(this.tester, this.controller)
    : focusNode = FocusNode(),
      scrollController = ScrollController();

  final WidgetTester tester;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final boundaryKey = GlobalKey();

  Future<void> pump({
    QuillPresentationGapPlan? plan,
    DefaultStyles? styles,
    QuillFinalTextStyleResolver? resolver,
    double width = 240,
    double height = 220,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          backgroundColor: _pageColor,
          body: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: width,
              height: height,
              child: QuillEditor(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                config: QuillEditorConfig(
                  padding: EdgeInsets.zero,
                  presentationGapPlan: plan,
                  customStyles: styles,
                  finalTextStyleResolver: resolver,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  RenderEditor get renderEditor => tester
      .state<QuillRawEditorState>(find.byType(QuillRawEditor))
      .renderEditor;

  QuillLayoutSnapshot get snapshot => renderEditor.getLayoutSnapshot();

  RenderEditableTextBlock blockAt(int documentOffset) {
    var child = renderEditor.firstChild;
    while (child != null) {
      if (child is RenderEditableTextBlock &&
          child.container.documentOffset == documentOffset) {
        return child;
      }
      child = renderEditor.childAfter(child);
    }
    throw StateError('No editable text block at $documentOffset.');
  }

  List<RenderEditableTextLine> linesIn(RenderEditableTextBlock block) {
    final result = <RenderEditableTextLine>[];
    var child = block.firstChild;
    while (child != null) {
      result.add(child as RenderEditableTextLine);
      child = block.childAfter(child);
    }
    return result;
  }

  Future<List<Color>> sampleColors(
    RenderBox source,
    List<Offset> sourceLocalPoints,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final capture = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image: image, bytes: bytes);
    });
    if (capture == null) throw StateError('Unable to capture rendered pixels.');
    final image = capture.image;
    final bytes = capture.bytes;
    if (bytes == null) throw StateError('Unable to read rendered pixels.');
    final result = <Color>[];
    for (final point in sourceLocalPoints) {
      final boundaryPoint = boundary.globalToLocal(source.localToGlobal(point));
      final x = boundaryPoint.dx.floor().clamp(0, image.width - 1);
      final y = boundaryPoint.dy.floor().clamp(0, image.height - 1);
      final byteOffset = (y * image.width + x) * 4;
      result.add(
        Color.fromARGB(
          bytes.getUint8(byteOffset + 3),
          bytes.getUint8(byteOffset),
          bytes.getUint8(byteOffset + 1),
          bytes.getUint8(byteOffset + 2),
        ),
      );
    }
    image.dispose();
    return result;
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

Document _singleBlockDocument(String text, Map<String, dynamic> attributes) {
  return Document.fromDelta(
    Delta()
      ..insert(text)
      ..insert('\n', attributes),
  );
}

void main() {
  testWidgets('Code first-line gap is outside padding and decoration pixels', (
    tester,
  ) async {
    final controller = QuillController(
      document: _singleBlockDocument('code', {'code-block': true}),
      selection: const TextSelection.collapsed(offset: 2),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(styles: _decoratedStyles);

    final delta = controller.document.toDelta().toJson();
    final undo = List<Delta>.of(controller.document.history.stack.undo);
    final redo = List<Delta>.of(controller.document.history.stack.redo);
    final baselineBlock = harness.blockAt(0);
    final baselineBlockHeight = baselineBlock.size.height;
    final baselinePaddingTop = baselineBlock.resolvedPadding!.top;
    final baselineFragment = harness.snapshot.fragments.single;

    const gap = 36.0;
    await harness.pump(
      styles: _decoratedStyles,
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 0, height: gap),
      ]),
    );

    final block = harness.blockAt(0);
    final line = harness.linesIn(block).single;
    final fragment = harness.snapshot.fragments.single;
    expect(block.presentationGapBefore, gap);
    expect(line.presentationGapBefore, 0);
    expect(
      block.presentationGapRects.first,
      const Rect.fromLTWH(0, 0, 240, gap),
    );
    expect(block.size.height, closeTo(baselineBlockHeight + gap, 0.01));
    expect(block.resolvedPadding!.top, baselinePaddingTop + gap);
    expect(fragment.rect.top, closeTo(baselineFragment.rect.top + gap, 0.01));
    expect(fragment.rect.height, baselineFragment.rect.height);
    expect(block.decoration, _decoratedStyles.code!.decoration);

    if (!kIsWeb) {
      final naturalSpacingTop = _decoratedStyles.code!.verticalSpacing.top;
      final colors = await harness.sampleColors(block, [
        Offset(block.size.width - 12, gap / 2),
        Offset(block.size.width / 2, gap + naturalSpacingTop + 3),
      ]);
      expect(colors[0], Colors.transparent);
      expect(colors[1], _codeColor);
    }

    final gapPoint = block.localToGlobal(const Offset(8, gap / 2));
    await tester.tapAt(gapPoint);
    await tester.pump();
    expect(controller.selection.extentOffset, 0);

    expect(controller.document.toDelta().toJson(), delta);
    expect(controller.document.history.stack.undo, undo);
    expect(controller.document.history.stack.redo, redo);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('BlockQuote border begins after its outer gap', (tester) async {
    final controller = QuillController(
      document: _singleBlockDocument('quote', {'blockquote': true}),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    const gap = 28.0;
    await harness.pump(
      styles: _decoratedStyles,
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 0, height: gap),
      ]),
    );

    final block = harness.blockAt(0);
    expect(block.presentationGapBefore, gap);
    expect(harness.linesIn(block).single.presentationGapBefore, 0);
    if (!kIsWeb) {
      final naturalSpacingTop = _decoratedStyles.quote!.verticalSpacing.top;
      final colors = await harness.sampleColors(block, [
        const Offset(1, gap / 2),
        Offset(1, gap + naturalSpacingTop + 6),
      ]);
      expect(colors[0], Colors.transparent);
      expect(colors[1], _quoteBorderColor);
    }
  });

  for (final entry in <String, Document>{
    'paragraph': Document.fromDelta(Delta()..insert('paragraph\n')),
    'header': _singleBlockDocument('heading', {'header': 2}),
  }.entries) {
    testWidgets('${entry.key} keeps natural geometry plus the requested gap', (
      tester,
    ) async {
      final controller = QuillController(
        document: entry.value,
        selection: const TextSelection.collapsed(offset: 0),
      );
      final harness = _EditorHarness(tester, controller);
      addTearDown(harness.dispose);
      await harness.pump();
      final baseline = harness.snapshot;
      final baselineHeight = harness.renderEditor.size.height;

      const gap = 23.0;
      await harness.pump(
        plan: QuillPresentationGapPlan(const [
          QuillPresentationGap(documentOffset: 0, height: gap),
        ]),
      );
      final presented = harness.snapshot;
      expect(
        presented.fragments.single.rect.top,
        closeTo(baseline.fragments.single.rect.top + gap, 0.01),
      );
      expect(
        presented.fragments.single.rect.size,
        baseline.fragments.single.rect.size,
      );
      expect(
        harness.renderEditor.size.height,
        closeTo(baselineHeight + gap, 0.01),
      );
    });
  }

  testWidgets('list first item is outer and later item remains internal', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('one')
          ..insert('\n', {'list': 'ordered'})
          ..insert('two')
          ..insert('\n', {'list': 'ordered'}),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump();
    final baseline = harness.snapshot;
    final baselineMarkers = [
      tester.getRect(find.byType(QuillNumberPoint).at(0)),
      tester.getRect(find.byType(QuillNumberPoint).at(1)),
    ];
    final secondOffset = baseline.fragments[1].documentRange.start;

    const firstGap = 21.0;
    await harness.pump(
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 0, height: firstGap),
      ]),
    );
    var block = harness.blockAt(0);
    var lines = harness.linesIn(block);
    expect(block.presentationGapBefore, firstGap);
    expect(lines[0].presentationGapBefore, 0);
    expect(lines[1].presentationGapBefore, 0);
    for (var index = 0; index < 2; index++) {
      final marker = tester.getRect(find.byType(QuillNumberPoint).at(index));
      expect(marker.top, closeTo(baselineMarkers[index].top + firstGap, 0.01));
      expect(marker.left, baselineMarkers[index].left);
      expect(marker.width, baselineMarkers[index].width);
    }

    const laterGap = 19.0;
    await harness.pump(
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: secondOffset, height: laterGap),
      ]),
    );
    block = harness.blockAt(0);
    lines = harness.linesIn(block);
    expect(block.presentationGapBefore, 0);
    expect(lines[0].presentationGapBefore, 0);
    expect(lines[1].presentationGapBefore, laterGap);
    final firstMarker = tester.getRect(find.byType(QuillNumberPoint).at(0));
    final secondMarker = tester.getRect(find.byType(QuillNumberPoint).at(1));
    expect(firstMarker, baselineMarkers[0]);
    expect(secondMarker.top, closeTo(baselineMarkers[1].top + laterGap, 0.01));
    expect(secondMarker.left, baselineMarkers[1].left);
    expect(
      harness.snapshot.fragments[1].rect.top,
      closeTo(baseline.fragments[1].rect.top + laterGap, 0.01),
    );
  });

  testWidgets('outer and soft gaps preserve snapshot natural coordinates', (
    tester,
  ) async {
    const codeText =
        'a long decorated code line wraps across several physical lines while '
        'remaining one logical document line';
    final delta = Delta()
      ..insert(codeText)
      ..insert('\n', {'code-block': true})
      ..insert('heading')
      ..insert('\n', {'header': 2});
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(styles: _decoratedStyles, width: 150, height: 320);
    final baseline = harness.snapshot;
    final code = baseline.fragments.first;
    final header = baseline.fragments.last;
    expect(code.physicalLines.length, greaterThanOrEqualTo(4));
    final softOffset = code.physicalLines[2].documentRange.start;
    final headerOffset = header.documentRange.start;

    const outerGap = 29.0;
    const softGap = 31.0;
    const headerGap = 17.0;
    await harness.pump(
      styles: _decoratedStyles,
      width: 150,
      height: 320,
      plan: QuillPresentationGapPlan([
        const QuillPresentationGap(documentOffset: 0, height: outerGap),
        QuillPresentationGap(documentOffset: softOffset, height: softGap),
        QuillPresentationGap(documentOffset: headerOffset, height: headerGap),
      ]),
    );

    final presented = harness.snapshot;
    final movedCode = presented.fragments.first;
    final movedHeader = presented.fragments.last;
    expect(movedCode.documentRange, code.documentRange);
    expect(movedHeader.documentRange, header.documentRange);
    expect(movedCode.rect.top - outerGap, closeTo(code.rect.top, 0.01));
    expect(
      movedHeader.rect.top - outerGap - softGap - headerGap,
      closeTo(header.rect.top, 0.01),
    );
    for (var index = 0; index < code.physicalLines.length; index++) {
      final naturalizedTop =
          movedCode.physicalLines[index].rect.top -
          outerGap -
          (index >= 2 ? softGap : 0);
      expect(naturalizedTop, closeTo(code.physicalLines[index].rect.top, 0.01));
      expect(
        movedCode.physicalLines[index].documentRange,
        code.physicalLines[index].documentRange,
      );
    }
    final block = harness.blockAt(0);
    final line = harness.linesIn(block).single;
    expect(block.presentationGapBefore, outerGap);
    expect(line.presentationGapBefore, 0);
    expect(line.presentationGapRects.single.height, softGap);
  });

  testWidgets('outer gap coordinates drive hit, caret, selection, and reveal', (
    tester,
  ) async {
    final prefix = List.generate(8, (index) => 'line $index\n').join();
    final codeOffset = prefix.length;
    final delta = Delta()
      ..insert(prefix)
      ..insert('code')
      ..insert('\n', {'code-block': true})
      ..insert('tail\n');
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: TextSelection.collapsed(offset: codeOffset + 2),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(styles: _decoratedStyles, height: 80);
    final baselineCaret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: codeOffset + 2),
    );
    final baselineSelection = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: 2, extentOffset: codeOffset + 2),
    );
    final baselineReveal = harness.renderEditor.getOffsetToRevealCursor(
      80,
      0,
      0,
    )!;
    final baselineScrollExtent =
        harness.scrollController.position.maxScrollExtent;
    final deltaBefore = controller.document.toDelta().toJson();
    final undo = List<Delta>.of(controller.document.history.stack.undo);
    final redo = List<Delta>.of(controller.document.history.stack.redo);

    const gap = 40.0;
    await harness.pump(
      styles: _decoratedStyles,
      height: 80,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: codeOffset, height: gap),
      ]),
    );
    final block = harness.blockAt(codeOffset);
    final blockOrigin = harness.renderEditor.globalToLocal(
      block.localToGlobal(Offset.zero),
    );
    final gapPoint = harness.renderEditor.localToGlobal(
      Offset(blockOrigin.dx + 8, blockOrigin.dy + gap / 2),
    );
    expect(
      harness.renderEditor.getPositionForOffset(gapPoint).offset,
      codeOffset,
    );

    final caret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: codeOffset + 2),
    );
    expect(caret.top, closeTo(baselineCaret.top + gap, 0.01));
    final selection = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: 2, extentOffset: codeOffset + 2),
    );
    expect(selection.first.point, baselineSelection.first.point);
    expect(
      selection.last.point.dy,
      closeTo(baselineSelection.last.point.dy + gap, 0.01),
    );
    final reversed = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: codeOffset + 2, extentOffset: 2),
    );
    expect(reversed.first.point.dy, selection.first.point.dy);
    expect(reversed.last.point.dy, selection.last.point.dy);

    final reveal = harness.renderEditor.getOffsetToRevealCursor(80, 0, 0)!;
    expect(reveal, closeTo(baselineReveal + gap, 0.01));
    expect(
      harness.scrollController.position.maxScrollExtent,
      closeTo(baselineScrollExtent + gap, 0.01),
    );
    expect(controller.document.toDelta().toJson(), deltaBefore);
    expect(controller.document.history.stack.undo, undo);
    expect(controller.document.history.stack.redo, redo);

    harness.scrollController.jumpTo(blockOrigin.dy);
    await tester.pump();
    final visibleGapPoint = block.localToGlobal(const Offset(8, gap / 2));
    expect(
      harness.renderEditor.getPositionForOffset(visibleGapPoint).offset,
      codeOffset,
    );
    expect(
      tester.getRect(find.byType(QuillEditor)).contains(visibleGapPoint),
      isTrue,
    );
    await tester.tapAt(visibleGapPoint);
    await tester.pump();
    expect(controller.selection.extentOffset, codeOffset);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('null and empty plans retain accepted block geometry', (
    tester,
  ) async {
    final controller = QuillController(
      document: _singleBlockDocument('code', {'code-block': true}),
      selection: const TextSelection.collapsed(offset: 2),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(styles: _decoratedStyles);
    final baseline = harness.snapshot;
    final baselineBlockSize = harness.blockAt(0).size;
    final baselineCaret = harness.renderEditor.getLocalRectForCaret(
      controller.selection.extent,
    );

    await harness.pump(
      styles: _decoratedStyles,
      plan: const QuillPresentationGapPlan.empty(),
    );
    final empty = harness.snapshot;
    expect(empty.editorRect, baseline.editorRect);
    expect(
      empty.fragments.map((fragment) => fragment.rect),
      baseline.fragments.map((fragment) => fragment.rect),
    );
    expect(harness.blockAt(0).size, baselineBlockSize);
    expect(
      harness.renderEditor.getLocalRectForCaret(controller.selection.extent),
      baselineCaret,
    );
  });

  testWidgets('final style resolver composes with an outer list gap', (
    tester,
  ) async {
    final delta = Delta()
      ..insert('ordinary ')
      ..insert('x', {'script': 'super', 'bold': true})
      ..insert('\n')
      ..insert('item')
      ..insert('\n', {'list': 'ordered'})
      ..insert('\n', {'list': 'ordered'});
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    final roles = <QuillFinalTextStyleRole>[];

    await harness.pump(
      resolver: (context, style, attributes, role) {
        roles.add(role);
        return style.copyWith(color: Colors.amber);
      },
    );
    final listOffset = harness.snapshot.fragments[1].documentRange.start;
    final emptyOffset = harness.snapshot.fragments.last.documentRange.start;
    controller.updateSelection(
      TextSelection.collapsed(offset: emptyOffset),
      ChangeSource.local,
    );
    roles.clear();

    await harness.pump(
      resolver: (context, style, attributes, role) {
        roles.add(role);
        return style.copyWith(color: Colors.amber);
      },
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: listOffset, height: 24),
      ]),
    );

    expect(roles, contains(QuillFinalTextStyleRole.text));
    expect(roles, contains(QuillFinalTextStyleRole.script));
    expect(roles, contains(QuillFinalTextStyleRole.listMarker));
    expect(roles, contains(QuillFinalTextStyleRole.emptyLineCaret));
    expect(harness.blockAt(listOffset).presentationGapBefore, 24);
    expect(controller.document.toDelta().toJson(), delta.toJson());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('many block-boundary gaps stay bounded', (tester) async {
    final delta = Delta();
    final gaps = <QuillPresentationGap>[];
    var documentOffset = 0;
    for (var index = 0; index < 400; index++) {
      final text = 'block $index';
      if (index % 10 == 0) {
        gaps.add(
          QuillPresentationGap(documentOffset: documentOffset, height: 3),
        );
      }
      delta
        ..insert(text)
        ..insert(
          '\n',
          index.isEven ? {'code-block': true} : {'blockquote': true},
        );
      documentOffset += text.length + 1;
    }
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    final stopwatch = Stopwatch()..start();

    await harness.pump(
      styles: _decoratedStyles,
      plan: QuillPresentationGapPlan(gaps),
    );
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'block-boundary presentation layout: '
      '${stopwatch.elapsedMilliseconds} ms, '
      '${harness.snapshot.fragments.length} blocks, ${gaps.length} gaps',
    );
    expect(harness.snapshot.fragments, hasLength(400));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(controller.document.toDelta().toJson(), delta.toJson());
  });

  testWidgets('later Code line gap remains an intra-block non-goal', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('first')
          ..insert('\n', {'code-block': true})
          ..insert('second')
          ..insert('\n', {'code-block': true}),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    const secondOffset = 6;
    await harness.pump(
      styles: _decoratedStyles,
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: secondOffset, height: 32),
      ]),
    );

    final block = harness.blockAt(0);
    final lines = harness.linesIn(block);
    expect(block.presentationGapBefore, 0);
    expect(lines.first.presentationGapBefore, 0);
    expect(lines.last.presentationGapBefore, 32);
  });
}
