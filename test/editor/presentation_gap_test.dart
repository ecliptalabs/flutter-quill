import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_block.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_quill/src/editor/widgets/text/text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestEmbedBuilder extends EmbedBuilder {
  const _TestEmbedBuilder();

  @override
  String get key => 'test';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return const SizedBox(
      width: 80,
      height: 70,
      child: ColoredBox(color: Colors.blue),
    );
  }
}

class _EditorHarness {
  _EditorHarness(this.tester, this.controller)
    : focusNode = FocusNode(),
      scrollController = ScrollController();

  final WidgetTester tester;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;

  Future<void> pump({
    QuillPresentationGapPlan? plan,
    double width = 220,
    double height = 180,
    Iterable<EmbedBuilder>? embedBuilders,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Scaffold(
            body: SizedBox(
              width: width,
              height: height,
              child: QuillEditor(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                config: QuillEditorConfig(
                  padding: EdgeInsets.zero,
                  presentationGapPlan: plan,
                  embedBuilders: embedBuilders,
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

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
  }
}

void main() {
  group('QuillPresentationGapPlan', () {
    test('canonicalizes order, ignores zero, and rejects invalid entries', () {
      final plan = QuillPresentationGapPlan(const [
        QuillPresentationGap(documentOffset: 9, height: 4),
        QuillPresentationGap(documentOffset: 2, height: 0),
        QuillPresentationGap(documentOffset: 5, height: 3),
      ]);

      expect(plan.gaps.map((gap) => gap.documentOffset), [5, 9]);
      expect(plan.gapBefore(5), 3);
      expect(plan.gapBefore(2), 0);
      expect(
        () => QuillPresentationGapPlan(const [
          QuillPresentationGap(documentOffset: 1, height: 2),
          QuillPresentationGap(documentOffset: 1, height: 3),
        ]),
        throwsArgumentError,
      );
      expect(
        () => QuillPresentationGapPlan(const [
          QuillPresentationGap(documentOffset: -1, height: 2),
        ]),
        throwsArgumentError,
      );
      expect(
        () => QuillPresentationGapPlan(const [
          QuillPresentationGap(documentOffset: 1, height: -2),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('QuillPresentationGapTransform', () {
    final transform = QuillPresentationGapTransform(const [
      QuillPresentationGapBoundary(naturalOffset: 10, height: 5),
      QuillPresentationGapBoundary(naturalOffset: 30, height: 7),
    ]);

    test('maps natural coordinates cumulatively at exact boundaries', () {
      expect(transform.naturalToPresented(9), 9);
      expect(transform.naturalToPresented(10), 15);
      expect(transform.naturalToPresented(29), 34);
      expect(transform.naturalToPresented(30), 42);
      expect(transform.naturalToPresented(40), 52);
    });

    test('reverse maps gap interiors to the following boundary', () {
      expect(transform.presentedToNatural(9), 9);
      expect(transform.presentedToNatural(10), 10);
      expect(transform.presentedToNatural(14.999), 10);
      expect(transform.presentedToNatural(15), 10);
      expect(transform.presentedToNatural(35), 30);
      expect(transform.presentedToNatural(41.999), 30);
      expect(transform.presentedToNatural(42), 30);
      expect(transform.presentedToNatural(52), 40);
    });

    test('round trips natural points without cumulative drift', () {
      for (var value = 0.0; value < 1000; value += 0.25) {
        expect(
          transform.presentedToNatural(transform.naturalToPresented(value)),
          value,
        );
      }
    });

    test('large prefix map keeps coordinate lookup bounded', () {
      final large = QuillPresentationGapTransform([
        for (var index = 1; index <= 500; index++)
          QuillPresentationGapBoundary(naturalOffset: index * 10, height: 3),
      ]);
      final stopwatch = Stopwatch()..start();
      var checksum = 0.0;
      for (var index = 0; index < 200000; index++) {
        final natural = (index % 60000) / 10;
        checksum += large.presentedToNatural(large.naturalToPresented(natural));
      }
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'presentation gap coordinate lookups: ${stopwatch.elapsedMicroseconds} us',
      );
      expect(checksum, greaterThan(0));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  testWidgets('block gap moves layout, caret, hit tests, and scroll extent', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('first\nsecond\nthird\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(height: 70);

    final deltaBefore = controller.document.toDelta().toJson();
    final baseline = harness.snapshot;
    final baselineHeight = harness.renderEditor.size.height;
    final secondOffset = baseline.fragments[1].documentRange.start;
    final beforeCaret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: secondOffset + 2),
    );
    final firstRect = baseline.fragments.first.rect;
    final secondRect = baseline.fragments[1].rect;

    await harness.pump(
      height: 70,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: secondOffset, height: 40),
      ]),
    );

    final presented = harness.snapshot;
    final afterCaret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: secondOffset + 2),
    );
    expect(presented.fragments.first.rect, firstRect);
    expect(presented.fragments[1].rect.top, closeTo(secondRect.top + 40, 0.01));
    expect(
      harness.renderEditor.size.height,
      closeTo(baselineHeight + 40, 0.01),
    );
    expect(afterCaret.top, closeTo(beforeCaret.top + 40, 0.01));

    final gapPoint = harness.renderEditor.localToGlobal(
      Offset(secondRect.left + 5, secondRect.top + 20),
    );
    expect(
      harness.renderEditor.getPositionForOffset(gapPoint).offset,
      secondOffset,
    );
    await tester.tapAt(gapPoint);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.selection.extentOffset, secondOffset);
    final roundTripPoint = harness.renderEditor.localToGlobal(
      afterCaret.center,
    );
    expect(
      harness.renderEditor.getPositionForOffset(roundTripPoint).offset,
      secondOffset + 2,
    );
    expect(controller.document.toDelta().toJson(), deltaBefore);
    expect(harness.scrollController.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('soft-line gap preserves one node and all coordinate paths', (
    tester,
  ) async {
    const text =
        'one continuous logical paragraph wraps across many physical lines '
        'without adding document nodes or synthetic newline characters';
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('$text\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 160, height: 120);

    final deltaBefore = controller.document.toDelta().toJson();
    final baseline = harness.snapshot;
    final lines = baseline.fragments.single.physicalLines;
    expect(lines.length, greaterThanOrEqualTo(4));
    final gapOffset = lines[2].documentRange.start;
    final beforeTarget = lines[2].rect;
    final beforeFollowing = lines[3].rect;
    final beforeCaret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: gapOffset),
    );
    final beforeSelection = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: gapOffset - 2, extentOffset: gapOffset + 2),
    );

    await harness.pump(
      width: 160,
      height: 120,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: gapOffset, height: 40),
      ]),
    );

    final presented = harness.snapshot;
    final presentedLines = presented.fragments.single.physicalLines;
    expect(
      presented.fragments.single.documentRange,
      baseline.fragments.single.documentRange,
    );
    expect(presentedLines[1].rect, lines[1].rect);
    expect(presentedLines[2].rect.top, closeTo(beforeTarget.top + 40, 0.01));
    expect(presentedLines[3].rect.top, closeTo(beforeFollowing.top + 40, 0.01));

    final afterCaret = harness.renderEditor.getLocalRectForCaret(
      TextPosition(offset: gapOffset),
    );
    expect(afterCaret.top, closeTo(beforeCaret.top + 40, 0.01));
    final afterSelection = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: gapOffset - 2, extentOffset: gapOffset + 2),
    );
    expect(afterSelection.first.point, beforeSelection.first.point);
    expect(
      afterSelection.last.point.dy,
      closeTo(beforeSelection.last.point.dy + 40, 0.01),
    );
    final reversed = harness.renderEditor.getEndpointsForSelection(
      TextSelection(baseOffset: gapOffset + 2, extentOffset: gapOffset - 2),
    );
    expect(reversed.first.point.dy, afterSelection.first.point.dy);
    expect(reversed.last.point.dy, afterSelection.last.point.dy);

    final gapPoint = harness.renderEditor.localToGlobal(
      Offset(beforeTarget.rectCenter.dx, beforeTarget.top + 20),
    );
    expect(
      harness.renderEditor.getPositionForOffset(gapPoint).offset,
      gapOffset,
    );
    await tester.tapAt(gapPoint);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.selection.extentOffset, gapOffset);
    final roundTrip = harness.renderEditor.localToGlobal(afterCaret.center);
    expect(
      harness.renderEditor.getPositionForOffset(roundTrip).offset,
      gapOffset,
    );
    final lineRender = tester.renderObject<RenderEditableTextLine>(
      find.byType(EditableTextLine).first,
    );
    expect(lineRender.presentationGapRects.single.height, 40);
    expect(controller.document.root.children.length, 1);
    expect(controller.document.toDelta().toJson(), deltaBefore);
  });

  testWidgets('vertical keyboard movement crosses a soft gap with no stop', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()..insert(
          'keyboard movement through a paragraph that wraps onto several visual lines cleanly\n',
        ),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 150);
    final lines = harness.snapshot.fragments.single.physicalLines;
    final gapOffset = lines[2].documentRange.start;
    final lineBoundary = harness.renderEditor.getLineAtOffset(
      TextPosition(offset: gapOffset + 1),
    );
    await harness.pump(
      width: 150,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: gapOffset, height: 45),
      ]),
    );

    final from = TextPosition(offset: lines[1].documentRange.start + 2);
    final below = harness.renderEditor.getTextPositionBelow(from);
    expect(
      below.offset,
      inInclusiveRange(
        lines[2].documentRange.start,
        lines[2].documentRange.end,
      ),
    );
    final above = harness.renderEditor.getTextPositionAbove(below);
    expect(
      above.offset,
      inInclusiveRange(
        lines[1].documentRange.start,
        lines[1].documentRange.end,
      ),
    );
    expect(
      harness.renderEditor.getLineAtOffset(TextPosition(offset: gapOffset + 1)),
      lineBoundary,
    );

    // Chrome's widget-test key synthesizer does not dispatch these editor
    // shortcuts. The renderer-level vertical and line-boundary assertions
    // above still run on Chrome; physical Arrow/Shift+Arrow runs on VM.
    if (!kIsWeb) {
      harness.focusNode.requestFocus();
      controller.updateSelection(
        TextSelection.collapsed(offset: gapOffset - 1),
        ChangeSource.local,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.selection, TextSelection.collapsed(offset: gapOffset));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(controller.selection.baseOffset, gapOffset);
      expect(controller.selection.extentOffset, gapOffset + 1);
    }
  });

  testWidgets(
    'dynamic plans retain controller, selection, history, and scroll',
    (tester) async {
      final text = List.generate(20, (index) => 'line $index').join('\n');
      final controller = QuillController(
        document: Document.fromDelta(Delta()..insert('$text\n')),
        selection: const TextSelection(baseOffset: 2, extentOffset: 18),
      );
      final harness = _EditorHarness(tester, controller);
      addTearDown(harness.dispose);
      await harness.pump(height: 100);
      harness.scrollController.jumpTo(20);
      await tester.pump();
      final selection = controller.selection;
      final delta = controller.document.toDelta().toJson();
      final undo = List<Delta>.of(controller.document.history.stack.undo);
      final redo = List<Delta>.of(controller.document.history.stack.redo);
      final offsets = harness.snapshot.fragments
          .skip(1)
          .take(2)
          .map((fragment) => fragment.documentRange.start)
          .toList();

      for (final plan in <QuillPresentationGapPlan?>[
        QuillPresentationGapPlan([
          QuillPresentationGap(documentOffset: offsets.first, height: 20),
        ]),
        QuillPresentationGapPlan([
          QuillPresentationGap(documentOffset: offsets.first, height: 20),
          QuillPresentationGap(documentOffset: offsets.last, height: 15),
        ]),
        null,
      ]) {
        await harness.pump(height: 100, plan: plan);
        expect(controller.selection, selection);
        expect(controller.document.toDelta().toJson(), delta);
        expect(controller.document.history.stack.undo, undo);
        expect(controller.document.history.stack.redo, redo);
        expect(harness.scrollController.offset, 20);
      }
    },
  );

  testWidgets('embed and list gaps move atomic content and marker together', (
    tester,
  ) async {
    final embedController = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('before\n')
          ..insert({'test': 'value'})
          ..insert('\nafter\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final embedHarness = _EditorHarness(tester, embedController);
    await embedHarness.pump(embedBuilders: const [_TestEmbedBuilder()]);
    final embed = embedHarness.snapshot.fragments.singleWhere(
      (fragment) => fragment.kind == QuillLayoutFragmentKind.embed,
    );
    final embedDelta = embedController.document.toDelta().toJson();
    await embedHarness.pump(
      embedBuilders: const [_TestEmbedBuilder()],
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(
          documentOffset: embed.documentRange.start,
          height: 30,
        ),
      ]),
    );
    final movedEmbed = embedHarness.snapshot.fragments.singleWhere(
      (fragment) => fragment.kind == QuillLayoutFragmentKind.embed,
    );
    expect(movedEmbed.rect.top, closeTo(embed.rect.top + 30, 0.01));
    expect(movedEmbed.embedRect, movedEmbed.rect);
    expect(movedEmbed.documentRange, embed.documentRange);
    final embedRect = movedEmbed.embedRect!;
    expect(
      embedHarness.renderEditor
          .getPositionForOffset(
            embedHarness.renderEditor.localToGlobal(
              Offset(embedRect.left + 1, embedRect.center.dy),
            ),
          )
          .offset,
      embed.documentRange.start,
    );
    expect(
      embedHarness.renderEditor
          .getPositionForOffset(
            embedHarness.renderEditor.localToGlobal(
              Offset(embedRect.right - 1, embedRect.center.dy),
            ),
          )
          .offset,
      embed.documentRange.start + 1,
    );
    final embedEndpoints = embedHarness.renderEditor.getEndpointsForSelection(
      TextSelection(
        baseOffset: embed.documentRange.start,
        extentOffset: embed.documentRange.start + 1,
      ),
    );
    expect(
      embedEndpoints.last.point.dx,
      greaterThan(embedEndpoints.first.point.dx),
    );
    expect(embedEndpoints.last.point.dy, embedEndpoints.first.point.dy);
    if (!kIsWeb) {
      embedHarness.focusNode.requestFocus();
      embedController.updateSelection(
        TextSelection.collapsed(offset: embed.documentRange.start),
        ChangeSource.local,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(
        embedController.selection,
        TextSelection.collapsed(offset: embed.documentRange.start + 1),
      );
    }
    expect(embedController.document.toDelta().toJson(), embedDelta);
    embedHarness.dispose();

    final listController = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('one')
          ..insert('\n', {'list': 'ordered'})
          ..insert('two')
          ..insert('\n', {'list': 'ordered'}),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final listHarness = _EditorHarness(tester, listController);
    addTearDown(listHarness.dispose);
    await listHarness.pump();
    final secondOffset = listHarness.snapshot.fragments[1].documentRange.start;
    final markerBefore = tester.getRect(find.byType(QuillNumberPoint).at(1));
    final bodyBefore = listHarness.snapshot.fragments[1].rect;
    await listHarness.pump(
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: secondOffset, height: 25),
      ]),
    );
    final markerAfter = tester.getRect(find.byType(QuillNumberPoint).at(1));
    final bodyAfter = listHarness.snapshot.fragments[1].rect;
    expect(markerAfter.top, closeTo(markerBefore.top + 25, 0.01));
    expect(bodyAfter.top, closeTo(bodyBefore.top + 25, 0.01));
    expect(markerAfter.left, markerBefore.left);
  });

  testWidgets('null and empty plans are geometry-compatible', (tester) async {
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('alpha\nbeta\n')),
      selection: const TextSelection.collapsed(offset: 3),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump();
    final baseline = harness.snapshot;
    final caret = harness.renderEditor.getLocalRectForCaret(
      controller.selection.extent,
    );
    final point = harness.renderEditor.localToGlobal(caret.center);
    final position = harness.renderEditor.getPositionForOffset(point);

    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 8),
      ChangeSource.local,
    );
    await tester.pump();
    expect(
      harness.snapshot.fragments.map((fragment) => fragment.rect),
      baseline.fragments.map((fragment) => fragment.rect),
    );
    controller.updateSelection(
      const TextSelection.collapsed(offset: 3),
      ChangeSource.local,
    );

    await harness.pump(plan: const QuillPresentationGapPlan.empty());
    final empty = harness.snapshot;
    expect(empty.editorRect, baseline.editorRect);
    expect(
      empty.fragments.map((fragment) => fragment.rect),
      baseline.fragments.map((fragment) => fragment.rect),
    );
    expect(
      harness.renderEditor.getLocalRectForCaret(controller.selection.extent),
      caret,
    );
    expect(harness.renderEditor.getPositionForOffset(point), position);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('gap height is exact under ordinary text scaling', (
    tester,
  ) async {
    final controller = QuillController(
      document: Document.fromDelta(
        Delta()..insert(
          'scaled text wraps across enough physical lines for a stable gap check\n',
        ),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 150, textScaler: const TextScaler.linear(1.4));
    final baseline = harness.snapshot;
    final gapOffset =
        baseline.fragments.single.physicalLines[1].documentRange.start;
    final baselineTop = baseline.fragments.single.physicalLines[1].rect.top;
    await harness.pump(
      width: 150,
      textScaler: const TextScaler.linear(1.4),
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: gapOffset, height: 37),
      ]),
    );
    expect(
      harness.snapshot.fragments.single.physicalLines[1].rect.top,
      closeTo(baselineTop + 37, 0.01),
    );
  });

  testWidgets(
    'pointer extension and reversal cross a soft gap without snapback',
    (tester) async {
      final controller = QuillController(
        document: Document.fromDelta(
          Delta()..insert(
            'pointer selection crosses several wrapped physical lines and reverses direction without restoring a stale range\n',
          ),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final harness = _EditorHarness(tester, controller);
      addTearDown(harness.dispose);
      await harness.pump(width: 150, height: 65);
      final lines = harness.snapshot.fragments.single.physicalLines;
      expect(lines.length, greaterThanOrEqualTo(4));
      final gapOffset = lines[2].documentRange.start;
      await harness.pump(
        width: 150,
        height: 65,
        plan: QuillPresentationGapPlan([
          QuillPresentationGap(documentOffset: gapOffset, height: 45),
        ]),
      );

      Offset globalPoint(int offset) {
        final caret = harness.renderEditor.getLocalRectForCaret(
          TextPosition(offset: offset),
        );
        return harness.renderEditor.localToGlobal(caret.center);
      }

      final middle = lines[1].documentRange.start + 1;
      final lower = lines[3].documentRange.start + 1;
      final upper = lines.first.documentRange.start + 1;
      harness.renderEditor
        ..handleDragStart(DragStartDetails(globalPosition: globalPoint(middle)))
        ..extendSelection(
          globalPoint(lower),
          cause: SelectionChangedCause.drag,
        );
      await tester.pump();
      expect(controller.selection, isA<DragTextSelection>());
      expect((controller.selection as DragTextSelection).first, isFalse);
      expect(controller.selection.extentOffset, lower);
      expect(harness.scrollController.offset, greaterThan(0));
      final downwardScrollOffset = harness.scrollController.offset;

      harness.renderEditor.extendSelection(
        globalPoint(upper),
        cause: SelectionChangedCause.drag,
      );
      await tester.pump();
      expect((controller.selection as DragTextSelection).first, isTrue);
      expect(controller.selection.start, upper);
      expect(controller.selection.end, middle);
      expect(harness.scrollController.offset, lessThan(downwardScrollOffset));
      harness.renderEditor.handleDragEnd(DragEndDetails());

      harness.renderEditor
        ..handleDragStart(DragStartDetails(globalPosition: globalPoint(lower)))
        ..extendSelection(
          globalPoint(upper),
          cause: SelectionChangedCause.drag,
        );
      await tester.pump();
      expect((controller.selection as DragTextSelection).first, isTrue);
      expect(controller.selection.start, upper);
      expect(controller.selection.end, lower);
      harness.renderEditor.handleDragEnd(DragEndDetails());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('caret reveal below multiple gaps includes cumulative extent', (
    tester,
  ) async {
    final text = List.generate(18, (index) => 'line $index').join('\n');
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('$text\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(height: 80);
    final fragments = harness.snapshot.fragments;
    final target = fragments[12].documentRange.start;
    harness.renderEditor.selection = TextSelection.collapsed(offset: target);
    final baselineReveal = harness.renderEditor.getOffsetToRevealCursor(
      80,
      0,
      0,
    )!;

    await harness.pump(
      height: 80,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(
          documentOffset: fragments[3].documentRange.start,
          height: 25,
        ),
        QuillPresentationGap(
          documentOffset: fragments[8].documentRange.start,
          height: 35,
        ),
      ]),
    );
    harness.renderEditor.selection = TextSelection.collapsed(offset: target);
    final presentedReveal = harness.renderEditor.getOffsetToRevealCursor(
      80,
      0,
      0,
    )!;
    expect(presentedReveal, closeTo(baselineReveal + 60, 0.01));
  });

  testWidgets('presentation gaps add no semantic text or traversal node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const text = 'semantic paragraph wraps onto multiple physical lines';
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('$text\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 150);
    final textFinder = find.text(text, findRichText: true);
    final baselineLabel = tester.getSemantics(textFinder).label;
    final gapOffset =
        harness.snapshot.fragments.single.physicalLines[1].documentRange.start;

    await harness.pump(
      width: 150,
      plan: QuillPresentationGapPlan([
        QuillPresentationGap(documentOffset: gapOffset, height: 33),
      ]),
    );
    expect(tester.getSemantics(textFinder).label, baselineLabel);
    expect(baselineLabel, contains(text));
    semantics.dispose();
  });

  testWidgets(
    'quote decoration exposes blank block and soft-line gap regions',
    (tester) async {
      final controller = QuillController(
        document: Document.fromDelta(
          Delta()
            ..insert(
              'quoted text wraps across multiple physical lines for clipping',
            )
            ..insert('\n', {'blockquote': true})
            ..insert('second quote row')
            ..insert('\n', {'blockquote': true}),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final harness = _EditorHarness(tester, controller);
      addTearDown(harness.dispose);
      await harness.pump(width: 150);
      final fragments = harness.snapshot.fragments;
      final softOffset = fragments.first.physicalLines[1].documentRange.start;
      final blockOffset = fragments[1].documentRange.start;
      await harness.pump(
        width: 150,
        plan: QuillPresentationGapPlan([
          QuillPresentationGap(documentOffset: softOffset, height: 21),
          QuillPresentationGap(documentOffset: blockOffset, height: 27),
        ]),
      );

      final quoteBlock = tester.renderObject<RenderEditableTextBlock>(
        find.byType(EditableTextBlock),
      );
      expect(
        quoteBlock.presentationGapRects.map((rect) => rect.height),
        containsAll(<double>[21, 27]),
      );
    },
  );

  testWidgets('synthetic many-line document lays out multiple gaps', (
    tester,
  ) async {
    final text = List.generate(900, (index) => 'word$index').join(' ');
    final controller = QuillController(
      document: Document.fromDelta(Delta()..insert('$text\n')),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final harness = _EditorHarness(tester, controller);
    addTearDown(harness.dispose);
    await harness.pump(width: 170, height: 100);
    final baselineHeight = harness.renderEditor.size.height;
    final lines = harness.snapshot.fragments.single.physicalLines;
    expect(lines.length, greaterThan(100));
    final selectedLines = <QuillPhysicalLineGeometry>[
      for (var index = 10; index < lines.length && index <= 200; index += 10)
        lines[index],
    ];
    final plan = QuillPresentationGapPlan([
      for (final line in selectedLines)
        QuillPresentationGap(
          documentOffset: line.documentRange.start,
          height: 8,
        ),
    ]);

    final stopwatch = Stopwatch()..start();
    await harness.pump(width: 170, height: 100, plan: plan);
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'presentation gap synthetic layout: ${stopwatch.elapsedMilliseconds} ms, '
      '${lines.length} physical lines, ${selectedLines.length} gaps',
    );
    expect(
      harness.renderEditor.size.height,
      closeTo(baselineHeight + selectedLines.length * 8, 0.01),
    );
  });
}

extension on Rect {
  Offset get rectCenter => center;
}
