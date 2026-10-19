import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_block.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_test/flutter_test.dart';

const _codeColor = Color(0xfffafafa);
const _sentinelColor = Color(0xffff00aa);
const _quoteColor = Color(0xffe91e63);

DefaultStyles _styles({Color codeColor = _codeColor}) => DefaultStyles(
  code: DefaultTextBlockStyle(
    const TextStyle(color: Colors.black, fontSize: 14, height: 1),
    HorizontalSpacing.zero,
    VerticalSpacing.zero,
    VerticalSpacing.zero,
    BoxDecoration(
      color: codeColor,
      border: const Border.fromBorderSide(BorderSide(color: Colors.black)),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
    ),
  ),
  quote: const DefaultTextBlockStyle(
    TextStyle(color: Colors.black, fontSize: 14, height: 1),
    HorizontalSpacing.zero,
    VerticalSpacing.zero,
    VerticalSpacing.zero,
    BoxDecoration(
      border: Border(left: BorderSide(width: 4, color: _quoteColor)),
    ),
  ),
);

Document _blockDocument(String attribute, int lineCount) {
  final delta = Delta();
  for (var index = 0; index < lineCount; index++) {
    delta
      ..insert('row$index')
      ..insert('\n', {attribute: true});
  }
  return Document.fromDelta(delta);
}

class _Harness {
  _Harness(this.tester, this.controller)
    : focusNode = FocusNode(),
      scrollController = ScrollController();

  final WidgetTester tester;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final boundaryKey = GlobalKey();

  Future<void> pump({
    QuillPresentationGapPlan plan = const QuillPresentationGapPlan.empty(),
    DefaultStyles? styles,
    double width = 240,
    double height = 320,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
                  customStyles: styles ?? _styles(),
                  presentationGapPlan: plan,
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

  RenderEditableTextBlock get block =>
      renderEditor.firstChild! as RenderEditableTextBlock;

  List<RenderEditableTextLine> get lines {
    final result = <RenderEditableTextLine>[];
    var child = block.firstChild;
    while (child != null) {
      result.add(child as RenderEditableTextLine);
      child = block.childAfter(child);
    }
    return result;
  }

  QuillLayoutSnapshot get snapshot => renderEditor.getLayoutSnapshot();

  Future<List<Color>> sampleColors(
    RenderBox source,
    Iterable<Offset> localPoints,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final capture = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image: image, bytes: bytes);
    });
    if (capture == null || capture.bytes == null) {
      throw StateError('Unable to capture rendered pixels.');
    }
    final result = <Color>[];
    for (final localPoint in localPoints) {
      final point = boundary.globalToLocal(source.localToGlobal(localPoint));
      final x = point.dx.floor().clamp(0, capture.image.width - 1);
      final y = point.dy.floor().clamp(0, capture.image.height - 1);
      final offset = (y * capture.image.width + x) * 4;
      result.add(
        Color.fromARGB(
          capture.bytes!.getUint8(offset + 3),
          capture.bytes!.getUint8(offset),
          capture.bytes!.getUint8(offset + 1),
          capture.bytes!.getUint8(offset + 2),
        ),
      );
    }
    capture.image.dispose();
    return result;
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

void main() {
  testWidgets('Code decoration is painted only in visible vertical slices', (
    tester,
  ) async {
    final controller = QuillController(
      document: _blockDocument('code-block', 2),
      selection: const TextSelection.collapsed(offset: 7),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    final delta = controller.document.toDelta().toJson();
    final undo = List<Delta>.of(controller.document.history.stack.undo);
    final redo = List<Delta>.of(controller.document.history.stack.redo);

    await harness.pump(styles: _styles(codeColor: _sentinelColor));
    final baseline = harness.snapshot;
    final baselineCaret = harness.renderEditor.getLocalRectForCaret(
      const TextPosition(offset: 7),
    );
    final baselineSelection = harness.renderEditor.getEndpointsForSelection(
      const TextSelection(baseOffset: 1, extentOffset: 7),
    );

    const gapHeight = 32.0;
    await harness.pump(
      styles: _styles(codeColor: _sentinelColor),
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 5, height: gapHeight),
      ]),
    );

    final block = harness.block;
    final gap = block.presentationGapRects.single;
    expect((block.decoration as BoxDecoration).color, _sentinelColor);
    expect(gap.left, greaterThan(0));
    expect(gap.right, lessThan(block.size.width));
    expect(harness.lines, hasLength(2));
    expect(find.byType(EditableTextBlock), findsOneWidget);
    expect(
      harness.snapshot.fragments.first.rect,
      baseline.fragments.first.rect,
    );
    expect(
      harness.snapshot.fragments.last.rect.top,
      closeTo(baseline.fragments.last.rect.top + gapHeight, 0.01),
    );
    final caret = harness.renderEditor.getLocalRectForCaret(
      const TextPosition(offset: 7),
    );
    expect(caret.top, closeTo(baselineCaret.top + gapHeight, 0.01));
    final selection = harness.renderEditor.getEndpointsForSelection(
      const TextSelection(baseOffset: 1, extentOffset: 7),
    );
    expect(selection.first.point, baselineSelection.first.point);
    expect(
      selection.last.point.dy,
      closeTo(baselineSelection.last.point.dy + gapHeight, 0.01),
    );
    final gapPoint = block.localToGlobal(gap.center);
    final hitOffset =
        harness.renderEditor.getPositionForOffset(gapPoint).offset;
    expect(hitOffset, inInclusiveRange(5, 9));

    if (!kIsWeb) {
      final colors = await harness.sampleColors(block, [
        Offset(block.size.width / 2, gap.top - 2),
        Offset(1, gap.top - 2),
        Offset(1, gap.center.dy),
        gap.center,
        Offset(block.size.width - 1, gap.center.dy),
        Offset(1, gap.bottom + 2),
        Offset(block.size.width / 2, gap.bottom + 2),
      ]);
      expect(colors[0], _sentinelColor);
      expect(colors[1], _sentinelColor);
      expect(colors[2], Colors.transparent);
      expect(colors[3], Colors.transparent);
      expect(colors[4], Colors.transparent);
      expect(colors[5], _sentinelColor);
      expect(colors[6], _sentinelColor);
    }

    await tester.tapAt(gapPoint);
    await tester.pump();
    expect(controller.selection.extentOffset, hitOffset);
    expect(controller.document.toDelta().toJson(), delta);
    expect(controller.document.history.stack.undo, undo);
    expect(controller.document.history.stack.redo, redo);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Code uses #FAFAFA before and after but not inside its gap', (
    tester,
  ) async {
    final controller = QuillController(
      document: _blockDocument('code-block', 2),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 5, height: 28),
      ]),
    );
    final block = harness.block;
    final gap = block.presentationGapRects.single;
    if (!kIsWeb) {
      final colors = await harness.sampleColors(block, [
        Offset(block.size.width / 2, gap.top - 2),
        gap.center,
        Offset(block.size.width / 2, gap.bottom + 2),
      ]);
      expect(colors, [_codeColor, Colors.transparent, _codeColor]);
    }
  });

  testWidgets('BlockQuote border stops and resumes across an internal gap', (
    tester,
  ) async {
    final controller = QuillController(
      document: _blockDocument('blockquote', 2),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 5, height: 30),
      ]),
    );
    final gap = harness.block.presentationGapRects.single;
    if (!kIsWeb) {
      final colors = await harness.sampleColors(harness.block, [
        Offset(1, gap.top - 2),
        Offset(1, gap.center.dy),
        Offset(1, gap.bottom + 2),
      ]);
      expect(colors, [_quoteColor, Colors.transparent, _quoteColor]);
    }
  });

  testWidgets('zero and multiple internal gaps paint deterministically', (
    tester,
  ) async {
    final controller = QuillController(
      document: _blockDocument('code-block', 5),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump();
    expect(harness.block.presentationGapRects, isEmpty);
    if (!kIsWeb) {
      expect(
        await harness.sampleColors(harness.block, [
          harness.block.size.center(Offset.zero),
        ]),
        [_codeColor],
      );
    }

    await harness.pump(
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 5, height: 20),
        QuillPresentationGap(documentOffset: 10, height: 24),
        QuillPresentationGap(documentOffset: 20, height: 18),
      ]),
    );
    final gaps = harness.block.presentationGapRects;
    expect(gaps, hasLength(3));
    if (!kIsWeb) {
      for (final gap in gaps) {
        final colors = await harness.sampleColors(harness.block, [
          Offset(1, gap.center.dy),
          gap.center,
          Offset(harness.block.size.width - 1, gap.center.dy),
        ]);
        expect(colors, everyElement(Colors.transparent));
      }
    }
  });

  testWidgets('outer block gap and internal gap remain independently blank', (
    tester,
  ) async {
    final controller = QuillController(
      document: _blockDocument('code-block', 2),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(
      plan: QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 0, height: 26),
        QuillPresentationGap(documentOffset: 5, height: 30),
      ]),
    );
    final block = harness.block;
    final gaps = block.presentationGapRects;
    expect(block.presentationGapBefore, 26);
    expect(harness.lines.first.presentationGapBefore, 0);
    expect(harness.lines.last.presentationGapBefore, 30);
    expect(gaps, hasLength(2));
    final outer = gaps.singleWhere((gap) => gap.top == 0);
    final internal = gaps.singleWhere((gap) => gap.top > 0);
    if (!kIsWeb) {
      final colors = await harness.sampleColors(block, [
        outer.center,
        Offset(1, internal.center.dy),
        internal.center,
        Offset(block.size.width - 1, internal.center.dy),
      ]);
      expect(colors, everyElement(Colors.transparent));
    }
  });

  testWidgets('soft-line Code gap clips the complete decoration width', (
    tester,
  ) async {
    const text =
        'a long Code line that wraps over several physical fragments so a '
        'presentation gap can be placed before a later soft line';
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert(text)
          ..insert('\n', {'code-block': true}),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 150);
    final baseline = harness.snapshot.fragments.single;
    expect(baseline.physicalLines.length, greaterThanOrEqualTo(3));
    final softOffset = baseline.physicalLines[1].documentRange.start;

    await harness.pump(
      width: 150,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: softOffset, height: 25),
      ]),
    );
    final moved = harness.snapshot.fragments.single;
    final gap = harness.block.presentationGapRects.single;
    expect(moved.physicalLines.first.rect, baseline.physicalLines.first.rect);
    expect(
      moved.physicalLines[1].rect.top,
      closeTo(baseline.physicalLines[1].rect.top + 25, 0.01),
    );
    if (!kIsWeb) {
      final colors = await harness.sampleColors(harness.block, [
        Offset(1, gap.center.dy),
        gap.center,
        Offset(harness.block.size.width - 1, gap.center.dy),
      ]);
      expect(colors, everyElement(Colors.transparent));
    }
  });

  testWidgets('decoration fragmentation scales with gap count', (tester) async {
    final delta = Delta();
    final gaps = <QuillPresentationGap>[];
    var offset = 0;
    for (var index = 0; index < 200; index++) {
      final text = 'row$index';
      if (index > 0 && index % 5 == 0) {
        gaps.add(QuillPresentationGap(documentOffset: offset, height: 3));
      }
      delta
        ..insert(text)
        ..insert('\n', {'code-block': true});
      offset += text.length + 1;
    }
    final controller = QuillController(
      document: Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _Harness(tester, controller);
    addTearDown(harness.dispose);
    final stopwatch = Stopwatch()..start();
    await harness.pump(height: 5000, plan: QuillPresentationGapPlan(gaps));
    stopwatch.stop();

    expect(harness.block.presentationGapRects, hasLength(gaps.length));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(controller.document.toDelta().toJson(), delta.toJson());
  });
}
