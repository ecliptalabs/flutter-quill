import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../presentation/presentation_gap.dart';
import 'box.dart';

class BaselineProxy extends SingleChildRenderObjectWidget {
  const BaselineProxy({
    super.key,
    super.child,
    this.textStyle,
    this.padding,
  });

  final TextStyle? textStyle;
  final EdgeInsets? padding;

  @override
  RenderBaselineProxy createRenderObject(BuildContext context) {
    return RenderBaselineProxy(
      null,
      textStyle!,
      padding,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderBaselineProxy renderObject) {
    renderObject
      ..textStyle = textStyle!
      ..padding = padding!;
  }
}

class RenderBaselineProxy extends RenderProxyBox {
  RenderBaselineProxy(
    RenderParagraph? super.child,
    TextStyle textStyle,
    EdgeInsets? padding,
  ) : _prototypePainter = TextPainter(
            text: TextSpan(text: ' ', style: textStyle),
            textDirection: TextDirection.ltr,
            strutStyle:
                StrutStyle.fromTextStyle(textStyle, forceStrutHeight: true));

  final TextPainter _prototypePainter;

  set textStyle(TextStyle value) {
    if (_prototypePainter.text!.style == value) {
      return;
    }
    _prototypePainter.text = TextSpan(text: ' ', style: value);
    markNeedsLayout();
  }

  EdgeInsets? _padding;

  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _prototypePainter.computeDistanceToActualBaseline(baseline);
  // SEE What happens + _padding?.top;

  @override
  void performLayout() {
    super.performLayout();
    _prototypePainter.layout();
  }

  @override
  void dispose() {
    super.dispose();
    _prototypePainter.dispose();
  }
}

class EmbedProxy extends SingleChildRenderObjectWidget {
  const EmbedProxy(Widget child, {super.key}) : super(child: child);

  @override
  RenderEmbedProxy createRenderObject(BuildContext context) =>
      RenderEmbedProxy(null);
}

class RenderEmbedProxy extends RenderProxyBox implements RenderContentProxyBox {
  RenderEmbedProxy(super.child);

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    if (!selection.isCollapsed) {
      return <TextBox>[
        TextBox.fromLTRBD(0, 0, size.width, size.height, TextDirection.ltr)
      ];
    }

    final left = selection.extentOffset == 0 ? 0.0 : size.width;
    final right = selection.extentOffset == 0 ? 0.0 : size.width;
    return <TextBox>[
      TextBox.fromLTRBD(left, 0, right, size.height, TextDirection.ltr)
    ];
  }

  @override
  double getFullHeightForCaret(TextPosition position) => size.height;

  @override
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    assert(
        position.offset == 1 || position.offset == 0 || position.offset == -1);
    return position.offset <= 0
        ? Offset.zero
        : Offset(size.width - caretPrototype.width, 0);
  }

  @override
  TextPosition getPositionForOffset(Offset offset) =>
      TextPosition(offset: offset.dx > size.width / 2 ? 1 : 0);

  @override
  TextRange getWordBoundary(TextPosition position) =>
      const TextRange(start: 0, end: 1);

  @override
  double get preferredLineHeight => size.height;

  @override
  bool get isEmbed => true;

  @override
  List<Rect> get presentationGapRects => const [];

  @override
  List<QuillPhysicalLineGeometry> getLayoutLines(int documentOffset) => [
        QuillPhysicalLineGeometry(
          documentRange:
              TextRange(start: documentOffset, end: documentOffset + 1),
          rect: Offset.zero & size,
        ),
      ];
}

class RichTextProxy extends SingleChildRenderObjectWidget {
  /// Child argument should be an instance of RichText widget.
  const RichTextProxy({
    required RichText super.child,
    required this.textStyle,
    required this.textAlign,
    required this.textDirection,
    required this.locale,
    required this.strutStyle,
    required this.textScaler,
    this.minimumHeight,
    this.caretVerticalOffset = 0,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
    this.presentationGaps = const {},
    super.key,
  });

  final TextStyle textStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale locale;
  final StrutStyle strutStyle;
  final double? minimumHeight;
  final double caretVerticalOffset;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Map<int, double> presentationGaps;

  @override
  RenderParagraphProxy createRenderObject(BuildContext context) {
    return RenderParagraphProxy(
        null,
        textStyle,
        textAlign,
        textDirection,
        textScaler,
        strutStyle,
        locale,
        textWidthBasis,
        textHeightBehavior,
        minimumHeight,
        caretVerticalOffset,
        presentationGaps);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderParagraphProxy renderObject) {
    renderObject
      ..textStyle = textStyle
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..locale = locale
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..minimumHeight = minimumHeight
      ..caretVerticalOffset = caretVerticalOffset
      ..presentationGaps = presentationGaps;
  }
}

class RenderParagraphProxy extends RenderProxyBox
    implements RenderContentProxyBox {
  RenderParagraphProxy(
    RenderParagraph? super.child,
    TextStyle textStyle,
    TextAlign textAlign,
    TextDirection textDirection,
    TextScaler textScaler,
    StrutStyle strutStyle,
    Locale locale,
    TextWidthBasis textWidthBasis,
    TextHeightBehavior? textHeightBehavior,
    double? minimumHeight,
    double caretVerticalOffset,
    Map<int, double> presentationGaps,
  ) : _prototypePainter = TextPainter(
          text: TextSpan(text: ' ', style: textStyle),
          textAlign: textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
          strutStyle: strutStyle,
          locale: locale,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
        ),
        _minimumHeight = minimumHeight,
        _caretVerticalOffset = caretVerticalOffset,
        _presentationGaps = Map.unmodifiable(presentationGaps);

  final TextPainter _prototypePainter;

  set textStyle(TextStyle value) {
    if (_prototypePainter.text!.style == value) {
      return;
    }
    _prototypePainter.text = TextSpan(text: ' ', style: value);
    markNeedsLayout();
  }

  set textAlign(TextAlign value) {
    if (_prototypePainter.textAlign == value) {
      return;
    }
    _prototypePainter.textAlign = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_prototypePainter.textDirection == value) {
      return;
    }
    _prototypePainter.textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_prototypePainter.textScaler == value) {
      return;
    }
    _prototypePainter.textScaler = value;
    markNeedsLayout();
  }

  set strutStyle(StrutStyle value) {
    if (_prototypePainter.strutStyle == value) {
      return;
    }
    _prototypePainter.strutStyle = value;
    markNeedsLayout();
  }

  set locale(Locale value) {
    if (_prototypePainter.locale == value) {
      return;
    }
    _prototypePainter.locale = value;
    markNeedsLayout();
  }

  set textWidthBasis(TextWidthBasis value) {
    if (_prototypePainter.textWidthBasis == value) {
      return;
    }
    _prototypePainter.textWidthBasis = value;
    markNeedsLayout();
  }

  set textHeightBehavior(TextHeightBehavior? value) {
    if (_prototypePainter.textHeightBehavior == value) {
      return;
    }
    _prototypePainter.textHeightBehavior = value;
    markNeedsLayout();
  }

  double? _minimumHeight;

  set minimumHeight(double? value) {
    if (_minimumHeight == value) {
      return;
    }
    _minimumHeight = value;
    markNeedsLayout();
  }

  double _caretVerticalOffset;

  set caretVerticalOffset(double value) {
    if (_caretVerticalOffset == value) {
      return;
    }
    _caretVerticalOffset = value;
    markNeedsPaint();
  }

  Map<int, double> _presentationGaps;

  set presentationGaps(Map<int, double> value) {
    if (mapEquals(_presentationGaps, value)) {
      return;
    }
    _presentationGaps = Map.unmodifiable(value);
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  QuillPresentationGapTransform? _gapTransform;
  List<int> _gapLineStartOffsets = const [];
  Map<int, double>? _physicalLineStarts;
  Size? _naturalSize;

  @override
  RenderParagraph? get child => super.child as RenderParagraph?;

  @override
  bool get isEmbed => false;

  @override
  List<Rect> get presentationGapRects {
    final transform = _gapTransform;
    if (transform == null || transform.isEmpty) return const [];
    return [
      for (var index = 0; index < transform.length; index++)
        Rect.fromLTWH(
          0,
          transform.presentedGapStart(index),
          size.width,
          transform.boundaryAt(index).height,
        ),
    ];
  }

  @override
  double get preferredLineHeight => _prototypePainter.preferredLineHeight;

  @override
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    final natural = child!.getOffsetForCaret(position, caretPrototype);
    final transform = _gapTransform;
    return Offset(
      natural.dx,
      (transform?.naturalToPresented(natural.dy) ?? natural.dy) +
          _caretVerticalOffset,
    );
  }

  @override
  TextPosition getPositionForOffset(Offset offset) {
    final transform = _gapTransform;
    if (transform == null || transform.isEmpty) {
      return child!.getPositionForOffset(offset);
    }
    final gapIndex = transform.gapIndexAtPresented(offset.dy);
    if (gapIndex != null) {
      return TextPosition(offset: _gapLineStartOffsets[gapIndex]);
    }
    return child!.getPositionForOffset(
      Offset(offset.dx, transform.presentedToNatural(offset.dy)),
    );
  }

  @override
  double? getFullHeightForCaret(TextPosition position) =>
      child!.getFullHeightForCaret(position);

  @override
  TextRange getWordBoundary(TextPosition position) =>
      child!.getWordBoundary(position);

  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    final boxes = child!.getBoxesForSelection(
      selection,
      boxHeightStyle: BoxHeightStyle.max,
    );
    final transform = _gapTransform;
    if (transform == null || transform.isEmpty) {
      return boxes;
    }
    return boxes.map((box) {
      final sampleY = box.top + (box.bottom - box.top) / 2;
      final shift = transform.cumulativeHeightAtNatural(sampleY);
      return TextBox.fromLTRBD(
        box.left,
        box.top + shift,
        box.right,
        box.bottom + shift,
        box.direction,
      );
    }).toList(growable: false);
  }

  double get _requestedGapHeight =>
      _presentationGaps.values.fold(0, (total, height) => total + height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width) + _requestedGapHeight;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width) + _requestedGapHeight;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final naturalSize = super.computeDryLayout(constraints);
    if (_presentationGaps.isEmpty) return naturalSize;
    return constraints.constrain(
      Size(naturalSize.width, naturalSize.height + _requestedGapHeight),
    );
  }

  @override
  void performLayout() {
    super.performLayout();
    _prototypePainter.layout(
        minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    final minimumHeight = _minimumHeight;
    if (minimumHeight != null) {
      size = constraints.constrain(
          Size(size.width, math.max(size.height, minimumHeight)));
    }
    _naturalSize = size;
    _physicalLineStarts = null;
    _rebuildPresentationTransform();
    final transform = _gapTransform;
    if (transform != null && !transform.isEmpty) {
      size = constraints.constrain(
        Size(size.width, size.height + transform.totalGapHeight),
      );
    }
  }

  void _rebuildPresentationTransform() {
    if (_presentationGaps.isEmpty || child == null) {
      _gapTransform = null;
      _gapLineStartOffsets = const [];
      return;
    }
    final textLength =
        child!.text.toPlainText(includeSemanticsLabels: false).length;
    if (textLength == 0) {
      _gapTransform = null;
      _gapLineStartOffsets = const [];
      return;
    }
    final physicalLineStarts =
        _physicalLineStarts ??= _measurePhysicalLineStarts(textLength);

    final applied = <MapEntry<int, QuillPresentationGapBoundary>>[];
    for (final entry in _presentationGaps.entries) {
      final naturalOffset = physicalLineStarts[entry.key];
      if (entry.key <= 0 || naturalOffset == null || entry.value <= 0) {
        continue;
      }
      applied.add(
        MapEntry(
          entry.key,
          QuillPresentationGapBoundary(
            naturalOffset: naturalOffset,
            height: entry.value,
          ),
        ),
      );
    }
    applied.sort(
      (a, b) => a.value.naturalOffset.compareTo(b.value.naturalOffset),
    );
    if (applied.isEmpty) {
      _gapTransform = null;
      _gapLineStartOffsets = const [];
      return;
    }
    _gapLineStartOffsets =
        applied.map((entry) => entry.key).toList(growable: false);
    _gapTransform = QuillPresentationGapTransform(
      applied.map((entry) => entry.value),
    );
  }

  Map<int, double> _measurePhysicalLineStarts(int textLength) {
    final starts = <int, double>{
      0: child!.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero).dy,
    };
    var previousY = starts[0]!;
    for (var offset = 1; offset < textLength; offset++) {
      final y = child!
          .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
          .dy;
      if ((y - previousY).abs() > precisionErrorTolerance) {
        starts[offset] = y;
        previousY = y;
      }
    }
    return starts;
  }

  @override
  List<QuillPhysicalLineGeometry> getLayoutLines(int documentOffset) {
    final naturalSize = _naturalSize ?? size;
    final textLength =
        child?.text.toPlainText(includeSemanticsLabels: false).length ?? 0;
    if (textLength == 0) {
      return [
        QuillPhysicalLineGeometry(
          documentRange: TextRange(start: documentOffset, end: documentOffset),
          rect: Offset.zero & size,
        ),
      ];
    }
    final starts =
        (_physicalLineStarts ??= _measurePhysicalLineStarts(textLength))
            .entries
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    final result = <QuillPhysicalLineGeometry>[];
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final naturalBottom = index + 1 < starts.length
          ? starts[index + 1].value
          : naturalSize.height;
      final transform = _gapTransform;
      final shift = transform?.cumulativeHeightAtNatural(start.value) ?? 0;
      result.add(
        QuillPhysicalLineGeometry(
          documentRange: TextRange(
            start: documentOffset + start.key,
            end: documentOffset +
                (index + 1 < starts.length
                    ? starts[index + 1].key
                    : textLength),
          ),
          rect: Rect.fromLTRB(
            0,
            start.value + shift,
            size.width,
            naturalBottom + shift,
          ),
        ),
      );
    }
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _gapTransform;
    final naturalSize = _naturalSize;
    if (transform == null || transform.isEmpty || naturalSize == null) {
      super.paint(context, offset);
      return;
    }
    var naturalTop = 0.0;
    var shift = 0.0;
    for (var index = 0; index < transform.length; index++) {
      final boundary = transform.boundaryAt(index);
      _paintNaturalSlice(
        context,
        offset,
        naturalTop,
        boundary.naturalOffset,
        shift,
        naturalSize.width,
      );
      naturalTop = boundary.naturalOffset;
      shift += boundary.height;
    }
    _paintNaturalSlice(
      context,
      offset,
      naturalTop,
      naturalSize.height,
      shift,
      naturalSize.width,
    );
  }

  void _paintNaturalSlice(
    PaintingContext context,
    Offset offset,
    double naturalTop,
    double naturalBottom,
    double shift,
    double width,
  ) {
    if (naturalBottom <= naturalTop) return;
    final clip = Rect.fromLTRB(
      0,
      naturalTop + shift,
      width,
      naturalBottom + shift,
    );
    context.pushClipRect(needsCompositing, offset, clip,
        (context, paintOffset) {
      context.paintChild(child!, paintOffset.translate(0, shift));
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final transform = _gapTransform;
    if (transform == null || transform.isEmpty) {
      return super.hitTestChildren(result, position: position);
    }
    if (transform.gapIndexAtPresented(position.dy) != null) {
      return false;
    }
    final naturalY = transform.presentedToNatural(position.dy);
    final shift = position.dy - naturalY;
    return result.addWithPaintOffset(
      offset: Offset(0, shift),
      position: position,
      hitTest: (result, transformed) =>
          child!.hitTest(result, position: transformed),
    );
  }

  @override
  bool hitTestSelf(Offset position) =>
      _gapTransform != null && size.contains(position);

  @override
  void dispose() {
    super.dispose();
    _prototypePainter.dispose();
  }
}
