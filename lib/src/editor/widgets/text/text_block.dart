import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../common/structs/horizontal_spacing.dart';
import '../../../common/structs/vertical_spacing.dart';
import '../../../common/utils/color.dart';
import '../../../common/utils/font.dart';
import '../../../controller/quill_controller.dart';
import '../../../delta/delta_diff.dart';
import '../../../document/attribute.dart';
import '../../../document/nodes/block.dart';
import '../../../document/nodes/line.dart';
import '../../../document/style.dart';
import '../../editor.dart';
import '../../embed/embed_editor_builder.dart';
import '../../presentation/presentation_gap.dart';
import '../../raw_editor/builders/leading_block_builder.dart';
import '../box.dart';
import '../cursor.dart';
import '../default_leading_components/leading_components.dart';
import '../default_styles.dart';
import '../delegate.dart';
import '../link.dart';
import 'text_line.dart';
import 'text_selection.dart';
import 'utils/text_block_utils.dart';

const List<int> arabianRomanNumbers = [
  1000,
  900,
  500,
  400,
  100,
  90,
  50,
  40,
  10,
  9,
  5,
  4,
  1,
];

const List<String> romanNumbers = [
  'M',
  'CM',
  'D',
  'CD',
  'C',
  'XC',
  'L',
  'XL',
  'X',
  'IX',
  'V',
  'IV',
  'I',
];

class _ListMarkerLayout {
  const _ListMarkerLayout({
    required this.width,
    required this.padding,
    required this.indentSize,
    required this.resolvedIndices,
    this.bulletAnchor,
  });

  final double width;
  final double padding;
  final double indentSize;
  final List<String?> resolvedIndices;
  final double? bulletAnchor;
}

class EditableTextBlock extends StatelessWidget {
  const EditableTextBlock({
    required this.block,
    required this.controller,
    required this.textDirection,
    required this.scrollBottomInset,
    required this.horizontalSpacing,
    required this.verticalSpacing,
    required this.textSelection,
    required this.color,
    required this.styles,
    required this.enableInteractiveSelection,
    required this.hasFocus,
    required this.contentPadding,
    required this.embedBuilder,
    required this.textSpanBuilder,
    required this.linkActionPicker,
    required this.cursorCont,
    required this.indentLevelCounts,
    required this.clearIndents,
    required this.onCheckboxTap,
    required this.readOnly,
    required this.customRecognizerBuilder,
    required this.composingRange,
    this.checkBoxReadOnly,
    this.onLaunchUrl,
    this.customStyleBuilder,
    this.customLinkPrefixes = const <String>[],
    this.customLeadingBlockBuilder,
    this.presentationGapPlan,
    super.key,
  });

  final Block block;
  final QuillController controller;
  final TextDirection textDirection;
  final double scrollBottomInset;
  final HorizontalSpacing horizontalSpacing;
  final VerticalSpacing verticalSpacing;
  final TextSelection textSelection;
  final Color color;
  final DefaultStyles? styles;
  final LeadingBlockNodeBuilder? customLeadingBlockBuilder;
  final bool enableInteractiveSelection;
  final bool hasFocus;
  final EdgeInsets? contentPadding;
  final EmbedsBuilder embedBuilder;
  final TextSpanBuilder textSpanBuilder;
  final LinkActionPicker linkActionPicker;
  final ValueChanged<String>? onLaunchUrl;
  final CustomRecognizerBuilder? customRecognizerBuilder;
  final CustomStyleBuilder? customStyleBuilder;
  final CursorCont cursorCont;
  final Map<int, int> indentLevelCounts;
  final bool clearIndents;
  final Function(int, bool) onCheckboxTap;
  final bool readOnly;
  final bool? checkBoxReadOnly;
  final List<String> customLinkPrefixes;
  final TextRange composingRange;
  final QuillPresentationGapPlan? presentationGapPlan;

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMediaQuery(context));

    final defaultStyles = QuillStyles.getStyles(context, false);
    return _EditableBlock(
      block: block,
      textDirection: textDirection,
      horizontalSpacing: horizontalSpacing,
      verticalSpacing: verticalSpacing,
      scrollBottomInset: scrollBottomInset,
      decoration:
          _getDecorationForBlock(block, defaultStyles) ?? const BoxDecoration(),
      contentPadding: contentPadding,
      children: _buildChildren(context, indentLevelCounts, clearIndents),
    );
  }

  BoxDecoration? _getDecorationForBlock(
    Block node,
    DefaultStyles? defaultStyles,
  ) {
    final attrs = block.style.attributes;
    if (attrs.containsKey(Attribute.blockQuote.key)) {
      // Verify if the direction is RTL and avoid passing the decoration
      // to the left when need to be on right side
      if (textDirection == TextDirection.rtl) {
        return defaultStyles!.quote!.decoration?.copyWith(
          border: Border(
            right: BorderSide(width: 4, color: Colors.grey.shade300),
          ),
        );
      }
      return defaultStyles!.quote!.decoration;
    }
    if (attrs.containsKey(Attribute.codeBlock.key)) {
      return defaultStyles!.code!.decoration;
    }
    return null;
  }

  List<Widget> _buildChildren(
    BuildContext context,
    Map<int, int> indentLevelCounts,
    bool clearIndents,
  ) {
    final defaultStyles = QuillStyles.getStyles(context, false);
    final numberPointWidthBuilder =
        defaultStyles?.lists?.numberPointWidthBuilder ??
        TextBlockUtils.defaultNumberPointWidthBuilder;
    final indentWidthBuilder =
        defaultStyles?.lists?.indentWidthBuilder ??
        TextBlockUtils.defaultIndentWidthBuilder;

    final lines = Iterable.castFrom<dynamic, Line>(block.children).toList();
    final count = lines.length;
    final children = <Widget>[];
    if (clearIndents) {
      indentLevelCounts.clear();
    }
    final markerStyles = lines
        .map((line) => _listMarkerStyle(line, defaultStyles!))
        .toList(growable: false);
    final markerLayout = _resolveListMarkerLayout(
      context: context,
      lines: lines,
      markerStyles: markerStyles,
      indentLevelCounts: indentLevelCounts,
      numberPointWidthBuilder: numberPointWidthBuilder,
    );
    var index = 0;
    for (final line in lines) {
      index++;
      final markerStyle = markerStyles[index - 1];
      final lineSpacing = _listIndentSpacing(
        context: context,
        line: line,
        count: count,
        markerStyle: markerStyle,
        markerWidth: markerLayout?.width,
        indentSize: markerLayout?.indentSize,
        indentWidthBuilder: indentWidthBuilder,
        numberPointWidthBuilder: numberPointWidthBuilder,
      );
      final markerAnchor = markerLayout?.bulletAnchor == null
          ? null
          : markerLayout!.bulletAnchor! +
                math.max<double>(0, lineSpacing.left - markerLayout.width);
      final editableTextLine = EditableTextLine(
        line,
        _buildLeading(
          context: context,
          line: line,
          index: index,
          indentLevelCounts: indentLevelCounts,
          count: count,
          markerStyle: markerStyle,
          markerWidth: markerLayout?.width,
          markerPadding: markerLayout?.padding,
          markerAnchor: markerAnchor,
          resolvedIndex: markerLayout?.resolvedIndices[index - 1],
        ),
        TextLine(
          line: line,
          textDirection: textDirection,
          embedBuilder: embedBuilder,
          textSpanBuilder: textSpanBuilder,
          customStyleBuilder: customStyleBuilder,
          styles: styles!,
          readOnly: readOnly,
          controller: controller,
          linkActionPicker: linkActionPicker,
          onLaunchUrl: onLaunchUrl,
          customLinkPrefixes: customLinkPrefixes,
          customRecognizerBuilder: customRecognizerBuilder,
          composingRange: composingRange,
          presentationGapPlan: presentationGapPlan,
        ),
        lineSpacing,
        _getSpacingForLine(line, index, count, defaultStyles),
        textDirection,
        textSelection,
        color,
        enableInteractiveSelection,
        hasFocus,
        MediaQuery.devicePixelRatioOf(context),
        cursorCont,
        styles!.inlineCode!,
        null,
        presentationGapBefore:
            presentationGapPlan?.gapBefore(line.documentOffset) ?? 0,
      );
      final nodeTextDirection = getDirectionOfNode(line, textDirection);
      children.add(
        Directionality(
          textDirection: nodeTextDirection,
          child: editableTextLine,
        ),
      );
    }
    return children.toList(growable: false);
  }

  _ListMarkerLayout? _resolveListMarkerLayout({
    required BuildContext context,
    required List<Line> lines,
    required List<TextStyle?> markerStyles,
    required Map<int, int> indentLevelCounts,
    required LeadingBlockNumberPointWidth numberPointWidthBuilder,
  }) {
    final listAttribute = block.style.attributes[Attribute.list.key];
    final isOrdered = listAttribute == Attribute.ol;
    final isUnordered = listAttribute == Attribute.ul;
    if (!isOrdered && !isUnordered) return null;

    final defaultStyles = QuillStyles.getStyles(context, false)!;
    final baseStyle = _markerTypography(
      (defaultStyles.paragraph?.style ?? const TextStyle(fontSize: 16)).merge(
        defaultStyles.lists?.style,
      ),
    );
    final baseFontSize = baseStyle.fontSize ?? 16;
    final count = lines.length;
    final resolvedIndices = List<String?>.filled(count, null);
    var configuredWidth = 0.0;
    var padding = 0.0;
    var widestText = 0.0;

    for (var index = 0; index < count; index++) {
      final line = lines[index];
      final markerStyle = markerStyles[index]!;
      final fontSize = markerStyle.fontSize ?? baseFontSize;
      configuredWidth = math.max(
        configuredWidth,
        numberPointWidthBuilder(fontSize, isOrdered ? count : 1),
      );
      padding = math.max(padding, fontSize / 2);

      final markerText = isOrdered
          ? '${LeadingConfig.resolveIndexNumberByIndent(index: index + 1, attrs: line.style.attributes, indentLevelCounts: indentLevelCounts)}.'
          : '•';
      if (isOrdered) {
        resolvedIndices[index] = markerText.substring(0, markerText.length - 1);
      }
      widestText = math.max(
        widestText,
        TextBlockUtils.measureMarkerTextWidth(
          context,
          markerText,
          markerStyle,
          getDirectionOfNode(line, textDirection),
        ),
      );
    }

    if (isOrdered) {
      return _ListMarkerLayout(
        width: math.max(configuredWidth, widestText + padding),
        padding: padding,
        indentSize: baseFontSize,
        resolvedIndices: resolvedIndices,
      );
    }

    final anchor = math.max(baseFontSize, widestText / 2);
    return _ListMarkerLayout(
      width: math.max(configuredWidth, anchor + widestText / 2 + padding),
      padding: padding,
      indentSize: baseFontSize,
      resolvedIndices: resolvedIndices,
      bulletAnchor: anchor,
    );
  }

  Widget? _buildLeading({
    required BuildContext context,
    required Line line,
    required int index,
    required Map<int, int> indentLevelCounts,
    required int count,
    required TextStyle? markerStyle,
    required double? markerWidth,
    required double? markerPadding,
    required double? markerAnchor,
    required String? resolvedIndex,
  }) {
    final defaultStyles = QuillStyles.getStyles(context, false)!;
    final fontSize = defaultStyles.paragraph?.style.fontSize ?? 16;
    final attrs = line.style.attributes;
    final numberPointWidthBuilder =
        defaultStyles.lists?.numberPointWidthBuilder ??
        TextBlockUtils.defaultNumberPointWidthBuilder;

    // Of the alignment buttons
    // final textAlign = line.style.attributes[Attribute.align.key]?.value != null
    //     ? getTextAlign(line.style.attributes[Attribute.align.key]?.value)
    //     : null;
    final attribute =
        attrs[Attribute.list.key] ?? attrs[Attribute.codeBlock.key];
    final isUnordered = attribute == Attribute.ul;
    final isOrdered = attribute == Attribute.ol;
    final isCheck =
        attribute == Attribute.checked || attribute == Attribute.unchecked;
    final isCodeBlock = attrs.containsKey(Attribute.codeBlock.key);
    if (attribute == null) return null;
    final leadingConfig = LeadingConfig(
      attribute: attribute,
      attrs: attrs,
      indentLevelCounts: indentLevelCounts,
      index: isOrdered || isCodeBlock ? index : null,
      resolvedIndex: isOrdered ? resolvedIndex : null,
      count: count,
      enabled: !isCheck ? null : !(checkBoxReadOnly ?? readOnly),
      style: () {
        if (isOrdered) {
          return markerStyle;
        }
        if (isUnordered) {
          return markerStyle;
        }
        if (isCheck) {
          return null;
        }
        return defaultStyles.code!.style.copyWith(
          color: defaultStyles.code!.style.color!.withValues(alpha: 0.4),
        );
      }(),
      width: () {
        if ((isOrdered || isUnordered) && markerWidth != null) {
          return markerWidth;
        }
        if (isOrdered || isCodeBlock) {
          return numberPointWidthBuilder(
            markerStyle?.fontSize ?? fontSize,
            count,
          );
        }
        if (isUnordered) {
          return numberPointWidthBuilder(markerStyle?.fontSize ?? fontSize, 1);
        }
        return null;
      }(),
      padding: () {
        if ((isOrdered || isUnordered) && markerPadding != null) {
          return markerPadding;
        }
        if (isOrdered || isUnordered) {
          return (markerStyle?.fontSize ?? fontSize) / 2;
        }
        if (isCodeBlock) {
          return fontSize;
        }
        return null;
      }(),
      anchor: isUnordered ? markerAnchor : null,
      lineSize: isCheck ? fontSize : null,
      uiBuilder: isCheck ? defaultStyles.lists?.checkboxUIBuilder : null,
      value: attribute == Attribute.checked,
      onCheckboxTap: !isCheck
          ? (value) {}
          : (value) => onCheckboxTap(line.documentOffset, value),
    );
    if (customLeadingBlockBuilder != null) {
      final leadingBlockNodeBuilder = customLeadingBlockBuilder?.call(
        line,
        leadingConfig,
      );
      if (leadingBlockNodeBuilder != null) {
        return leadingBlockNodeBuilder;
      }
    }

    if (isOrdered) {
      return numberPointLeading(leadingConfig);
    }

    if (isUnordered) {
      return bulletPointLeading(leadingConfig);
    }

    if (isCheck) {
      return checkboxLeading(leadingConfig);
    }
    if (isCodeBlock) {
      return codeBlockLineNumberLeading(leadingConfig);
    }
    return null;
  }

  TextStyle? _listMarkerStyle(Line line, DefaultStyles defaultStyles) {
    final listAttribute = line.style.attributes[Attribute.list.key];
    if (listAttribute != Attribute.ul && listAttribute != Attribute.ol) {
      return null;
    }

    var style = _markerTypography(
      (defaultStyles.paragraph?.style ?? const TextStyle(fontSize: 16)).merge(
        defaultStyles.lists?.style,
      ),
    );
    if (listAttribute == Attribute.ul && style.fontWeight == null) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }

    final customAttributes = <Attribute>[...line.style.values];
    if (line.isNotEmpty) {
      final firstRunStyle = line.children.first.style;
      style = style.merge(
        _markerStyleForAttributes(firstRunStyle, defaultStyles),
      );
      customAttributes.addAll(firstRunStyle.values);
    } else {
      var emptyLineStyle = controller.document.collectStyle(
        line.documentOffset,
        0,
      );
      if (_isActiveEmptyLine(line)) {
        emptyLineStyle = emptyLineStyle.mergeAll(controller.toggledStyle);
      }
      style = style.merge(
        _markerStyleForAttributes(emptyLineStyle, defaultStyles),
      );
      customAttributes.addAll(emptyLineStyle.values);
    }

    final styleBuilder = customStyleBuilder;
    if (styleBuilder != null) {
      for (final attribute in customAttributes) {
        if (!_isMarkerCustomStyleAttribute(attribute)) {
          continue;
        }
        style = style.merge(_markerTypography(styleBuilder(attribute)));
      }
    }

    return _markerTypography(
      style,
    ).copyWith(decoration: TextDecoration.none, backgroundColor: null);
  }

  bool _isActiveEmptyLine(Line line) {
    return line.isEmpty &&
        textSelection.isCollapsed &&
        textSelection.extentOffset == line.documentOffset;
  }

  bool _isMarkerCustomStyleAttribute(Attribute attribute) {
    return !<String>{
      Attribute.background.key,
      Attribute.inlineCode.key,
      Attribute.link.key,
      Attribute.script.key,
      Attribute.strikeThrough.key,
      Attribute.underline.key,
    }.contains(attribute.key);
  }

  TextStyle _markerStyleForAttributes(
    Style attributes,
    DefaultStyles defaultStyles,
  ) {
    var style = const TextStyle();
    if (attributes.containsKey(Attribute.bold.key)) {
      style = style.merge(defaultStyles.bold);
    }
    if (attributes.containsKey(Attribute.small.key)) {
      style = style.merge(defaultStyles.small);
    }

    final font = attributes.attributes[Attribute.font.key];
    if (font?.value != null) {
      style = style.merge(TextStyle(fontFamily: font!.value));
    }

    final size = attributes.attributes[Attribute.size.key];
    if (size?.value != null) {
      final fontSize = getFontSizeAsDouble(
        size!.value,
        defaultStyles: defaultStyles,
      );
      if (fontSize != null) {
        style = style.merge(TextStyle(fontSize: fontSize));
      }
    }

    final color = attributes.attributes[Attribute.color.key];
    if (color?.value is String) {
      style = style.merge(
        TextStyle(color: stringToColor(color!.value, null, defaultStyles)),
      );
    }

    return _markerTypography(style);
  }

  TextStyle _markerTypography(TextStyle style) {
    return TextStyle(
      color: style.color,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      height: style.height,
    );
  }

  HorizontalSpacing _listIndentSpacing({
    required BuildContext context,
    required Line line,
    required int count,
    required TextStyle? markerStyle,
    required double? markerWidth,
    required double? indentSize,
    required LeadingBlockIndentWidth indentWidthBuilder,
    required LeadingBlockNumberPointWidth numberPointWidthBuilder,
  }) {
    if (markerStyle == null) {
      return indentWidthBuilder(block, context, count, numberPointWidthBuilder);
    }

    final fontSize = markerStyle.fontSize ?? 16;
    final attrs = line.style.attributes;
    final listAttribute = attrs[Attribute.list.key];
    final effectiveMarkerWidth =
        markerWidth ??
        numberPointWidthBuilder(
          fontSize,
          listAttribute == Attribute.ol ? count : 1,
        );
    if (indentWidthBuilder != TextBlockUtils.defaultIndentWidthBuilder) {
      final customSpacing = indentWidthBuilder(
        block,
        context,
        count,
        (_, __) => effectiveMarkerWidth,
      );
      return customSpacing.copyWith(
        left: math.max(customSpacing.left, effectiveMarkerWidth),
      );
    }
    final indent = attrs[Attribute.indent.key]?.value as int? ?? 0;
    return HorizontalSpacing(
      effectiveMarkerWidth + (indentSize ?? fontSize) * indent,
      0,
    );
  }

  VerticalSpacing _getSpacingForLine(
    Line node,
    int index,
    int count,
    DefaultStyles? defaultStyles,
  ) {
    var top = 0.0, bottom = 0.0;

    final attrs = block.style.attributes;
    if (attrs.containsKey(Attribute.header.key)) {
      final level = attrs[Attribute.header.key]!.value;
      switch (level) {
        case 1:
          top = defaultStyles!.h1!.verticalSpacing.top;
          bottom = defaultStyles.h1!.verticalSpacing.bottom;
          break;
        case 2:
          top = defaultStyles!.h2!.verticalSpacing.top;
          bottom = defaultStyles.h2!.verticalSpacing.bottom;
          break;
        case 3:
          top = defaultStyles!.h3!.verticalSpacing.top;
          bottom = defaultStyles.h3!.verticalSpacing.bottom;
          break;
        case 4:
          top = defaultStyles!.h4!.verticalSpacing.top;
          bottom = defaultStyles.h4!.verticalSpacing.bottom;
          break;
        case 5:
          top = defaultStyles!.h5!.verticalSpacing.top;
          bottom = defaultStyles.h5!.verticalSpacing.bottom;
          break;
        case 6:
          top = defaultStyles!.h6!.verticalSpacing.top;
          bottom = defaultStyles.h6!.verticalSpacing.bottom;
          break;
        default:
          throw ArgumentError('Invalid level $level');
      }
    } else {
      final VerticalSpacing lineSpacing;
      if (attrs.containsKey(Attribute.blockQuote.key)) {
        lineSpacing = defaultStyles!.quote!.lineSpacing;
      } else if (attrs.containsKey(Attribute.indent.key)) {
        lineSpacing = defaultStyles!.indent!.lineSpacing;
      } else if (attrs.containsKey(Attribute.list.key)) {
        lineSpacing = defaultStyles!.lists!.lineSpacing;
      } else if (attrs.containsKey(Attribute.codeBlock.key)) {
        lineSpacing = defaultStyles!.code!.lineSpacing;
      } else if (attrs.containsKey(Attribute.align.key)) {
        lineSpacing = defaultStyles!.align!.lineSpacing;
      } else {
        // use paragraph linespacing as a default
        lineSpacing = defaultStyles!.paragraph!.lineSpacing;
      }
      top = lineSpacing.top;
      bottom = lineSpacing.bottom;
    }

    if (index == 1) {
      top = 0.0;
    }

    if (index == count) {
      bottom = 0.0;
    }

    return VerticalSpacing(top, bottom);
  }
}

class RenderEditableTextBlock extends RenderEditableContainerBox
    implements RenderEditableBox {
  RenderEditableTextBlock({
    required Block block,
    required super.textDirection,
    required EdgeInsetsGeometry padding,
    required super.scrollBottomInset,
    required Decoration decoration,
    super.children,
    EdgeInsets contentPadding = EdgeInsets.zero,
  }) : _decoration = decoration,
       _configuration = ImageConfiguration(textDirection: textDirection),
       _savedPadding = padding,
       _contentPadding = contentPadding,
       super(container: block, padding: padding.add(contentPadding));

  EdgeInsetsGeometry _savedPadding;
  EdgeInsets _contentPadding;

  set contentPadding(EdgeInsets value) {
    if (_contentPadding == value) return;
    _contentPadding = value;
    super.setPadding(_savedPadding.add(_contentPadding));
  }

  @override
  void setPadding(EdgeInsetsGeometry value) {
    super.setPadding(value.add(_contentPadding));
    _savedPadding = value;
  }

  BoxPainter? _painter;

  Decoration get decoration => _decoration;
  Decoration _decoration;

  set decoration(Decoration value) {
    if (value == _decoration) return;
    _painter?.dispose();
    _painter = null;
    _decoration = value;
    markNeedsPaint();
  }

  ImageConfiguration get configuration => _configuration;
  ImageConfiguration _configuration;

  set configuration(ImageConfiguration value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsPaint();
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    final child = childAtPosition(position);
    final rangeInChild = child.getLineBoundary(
      TextPosition(
        offset: position.offset - child.container.offset,
        affinity: position.affinity,
      ),
    );
    return TextRange(
      start: rangeInChild.start + child.container.offset,
      end: rangeInChild.end + child.container.offset,
    );
  }

  @override
  Offset getOffsetForCaret(TextPosition position) {
    final child = childAtPosition(position);
    return child.getOffsetForCaret(
          TextPosition(
            offset: position.offset - child.container.offset,
            affinity: position.affinity,
          ),
        ) +
        (child.parentData as BoxParentData).offset;
  }

  @override
  TextPosition getPositionForOffset(Offset offset) {
    final child = childAtOffset(offset);
    final parentData = child.parentData as BoxParentData;
    final localPosition = child.getPositionForOffset(
      offset - parentData.offset,
    );
    return TextPosition(
      offset: localPosition.offset + child.container.offset,
      affinity: localPosition.affinity,
    );
  }

  @override
  TextRange getWordBoundary(TextPosition position) {
    final child = childAtPosition(position);
    final nodeOffset = child.container.offset;
    final childWord = child.getWordBoundary(
      TextPosition(offset: position.offset - nodeOffset),
    );
    return TextRange(
      start: childWord.start + nodeOffset,
      end: childWord.end + nodeOffset,
    );
  }

  @override
  TextPosition? getPositionAbove(TextPosition position) {
    assert(position.offset < container.length);

    final child = childAtPosition(position);
    final childLocalPosition = TextPosition(
      offset: position.offset - child.container.offset,
    );
    final result = child.getPositionAbove(childLocalPosition);
    if (result != null) {
      return TextPosition(offset: result.offset + child.container.offset);
    }

    final sibling = childBefore(child);
    if (sibling == null) {
      return null;
    }

    final caretOffset = child.getOffsetForCaret(childLocalPosition);
    final testPosition = TextPosition(offset: sibling.container.length - 1);
    final testOffset = sibling.getOffsetForCaret(testPosition);
    final finalOffset = Offset(caretOffset.dx, testOffset.dy);
    return TextPosition(
      offset:
          sibling.container.offset +
          sibling.getPositionForOffset(finalOffset).offset,
    );
  }

  @override
  TextPosition? getPositionBelow(TextPosition position) {
    assert(position.offset < container.length);

    final child = childAtPosition(position);
    final childLocalPosition = TextPosition(
      offset: position.offset - child.container.offset,
    );
    final result = child.getPositionBelow(childLocalPosition);
    if (result != null) {
      return TextPosition(offset: result.offset + child.container.offset);
    }

    final sibling = childAfter(child);
    if (sibling == null) {
      return null;
    }

    final caretOffset = child.getOffsetForCaret(childLocalPosition);
    final testOffset = sibling.getOffsetForCaret(const TextPosition(offset: 0));
    final finalOffset = Offset(caretOffset.dx, testOffset.dy);
    return TextPosition(
      offset:
          sibling.container.offset +
          sibling.getPositionForOffset(finalOffset).offset,
    );
  }

  @override
  double preferredLineHeight(TextPosition position) {
    final child = childAtPosition(position);
    return child.preferredLineHeight(
      TextPosition(offset: position.offset - child.container.offset),
    );
  }

  @override
  TextSelectionPoint getBaseEndpointForSelection(TextSelection selection) {
    if (selection.isCollapsed) {
      return TextSelectionPoint(
        Offset(0, preferredLineHeight(selection.extent)) +
            getOffsetForCaret(selection.extent),
        null,
      );
    }

    final baseNode = container.queryChild(selection.start, false).node;
    var baseChild = firstChild;
    while (baseChild != null) {
      if (baseChild.container == baseNode) {
        break;
      }
      baseChild = childAfter(baseChild);
    }
    assert(baseChild != null);

    final basePoint = baseChild!.getBaseEndpointForSelection(
      localSelection(baseChild.container, selection, true),
    );
    return TextSelectionPoint(
      basePoint.point + (baseChild.parentData as BoxParentData).offset,
      basePoint.direction,
    );
  }

  @override
  TextSelectionPoint getExtentEndpointForSelection(TextSelection selection) {
    if (selection.isCollapsed) {
      return TextSelectionPoint(
        Offset(0, preferredLineHeight(selection.extent)) +
            getOffsetForCaret(selection.extent),
        null,
      );
    }

    final extentNode = container.queryChild(selection.end, false).node;

    var extentChild = firstChild;
    while (extentChild != null) {
      if (extentChild.container == extentNode) {
        break;
      }
      extentChild = childAfter(extentChild);
    }
    assert(extentChild != null);

    final extentPoint = extentChild!.getExtentEndpointForSelection(
      localSelection(extentChild.container, selection, true),
    );
    return TextSelectionPoint(
      extentPoint.point + (extentChild.parentData as BoxParentData).offset,
      extentPoint.direction,
    );
  }

  @override
  void detach() {
    _painter?.dispose();
    _painter = null;
    super.detach();
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintDecoration(context, offset);
    defaultPaint(context, offset);
  }

  void _paintDecoration(PaintingContext context, Offset offset) {
    _painter ??= _decoration.createBoxPainter(markNeedsPaint);

    final decorationPadding = resolvedPadding! - _contentPadding;

    final filledConfiguration = configuration.copyWith(
      size: decorationPadding.deflateSize(size),
    );
    final debugSaveCount = context.canvas.getSaveCount();

    final decorationOffset = offset.translate(
      decorationPadding.left,
      decorationPadding.top,
    );
    final gaps = presentationGapRects;
    if (gaps.isNotEmpty) {
      final bounds = offset & size;
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds);
      for (final gap in gaps) {
        path.addRect(gap.shift(offset));
      }
      context.canvas
        ..save()
        ..clipPath(path);
    }
    _painter!.paint(context.canvas, decorationOffset, filledConfiguration);
    if (gaps.isNotEmpty) context.canvas.restore();
    if (debugSaveCount != context.canvas.getSaveCount()) {
      throw StateError(
        '${_decoration.runtimeType} painter had mismatching save and  '
        'restore calls.',
      );
    }
    if (decoration.isComplex) {
      context.setIsComplexHint();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  Rect getLocalRectForCaret(TextPosition position) {
    final child = childAtPosition(position);
    final localPosition = TextPosition(
      offset: position.offset - child.container.offset,
      affinity: position.affinity,
    );
    final parentData = child.parentData as BoxParentData;
    return child.getLocalRectForCaret(localPosition).shift(parentData.offset);
  }

  @override
  TextPosition globalToLocalPosition(TextPosition position) {
    assert(
      container.containsOffset(position.offset) || container.length == 0,
      'The provided text position is not in the current node',
    );
    return TextPosition(
      offset: position.offset - container.documentOffset,
      affinity: position.affinity,
    );
  }

  @override
  Rect getCaretPrototype(TextPosition position) {
    final child = childAtPosition(position);
    final localPosition = TextPosition(
      offset: position.offset - child.container.offset,
      affinity: position.affinity,
    );
    return child.getCaretPrototype(localPosition);
  }

  @override
  List<QuillLayoutFragment> getLayoutFragments(Offset offset) {
    final result = <QuillLayoutFragment>[];
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData as EditableContainerParentData;
      result.addAll(child.getLayoutFragments(offset + parentData.offset));
      child = parentData.nextSibling;
    }
    return result;
  }

  @override
  List<Rect> get presentationGapRects {
    final result = <Rect>[];
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData as EditableContainerParentData;
      result.addAll(
        child.presentationGapRects.map((rect) => rect.shift(parentData.offset)),
      );
      child = parentData.nextSibling;
    }
    return result;
  }
}

class _EditableBlock extends MultiChildRenderObjectWidget {
  const _EditableBlock({
    required this.block,
    required this.textDirection,
    required this.horizontalSpacing,
    required this.verticalSpacing,
    required this.scrollBottomInset,
    required this.decoration,
    required this.contentPadding,
    required super.children,
  });

  final Block block;
  final TextDirection textDirection;
  final HorizontalSpacing horizontalSpacing;
  final VerticalSpacing verticalSpacing;
  final double scrollBottomInset;
  final Decoration decoration;
  final EdgeInsets? contentPadding;

  EdgeInsets get _padding => EdgeInsets.only(
    left: horizontalSpacing.left,
    right: horizontalSpacing.right,
    top: verticalSpacing.top,
    bottom: verticalSpacing.bottom,
  );

  EdgeInsets get _contentPadding => contentPadding ?? EdgeInsets.zero;

  @override
  RenderEditableTextBlock createRenderObject(BuildContext context) {
    return RenderEditableTextBlock(
      block: block,
      textDirection: textDirection,
      padding: _padding,
      scrollBottomInset: scrollBottomInset,
      decoration: decoration,
      contentPadding: _contentPadding,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderEditableTextBlock renderObject,
  ) {
    renderObject
      ..setContainer(block)
      ..textDirection = textDirection
      ..scrollBottomInset = scrollBottomInset
      ..setPadding(_padding)
      ..decoration = decoration
      ..contentPadding = _contentPadding;
  }
}
