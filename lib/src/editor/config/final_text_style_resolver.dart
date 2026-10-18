import 'package:flutter/widgets.dart';

import '../../document/style.dart';

/// The rendering path for a style passed to [QuillFinalTextStyleResolver].
enum QuillFinalTextStyleRole {
  /// Ordinary document text, including text in block-level formats.
  text,

  /// Superscript or subscript text after its size and weight are resolved.
  script,

  /// The marker rendered before an ordered or unordered list item.
  listMarker,

  /// The insertion style used to measure an active empty line's caret.
  emptyLineCaret,
}

/// Resolves the final style used by a Flutter Quill text rendering path.
///
/// [resolvedStyle] includes the block, line, and inline styling that Flutter
/// Quill would otherwise render. [effectiveAttributes] combines the relevant
/// line and inline attributes for the rendering path. The returned style is
/// used as-is; Flutter Quill does not merge its own styling over it afterward.
///
/// Callers that only want to reconcile a typeface should normally return
/// `resolvedStyle.copyWith(...)` so all other resolved properties are kept.
typedef QuillFinalTextStyleResolver =
    TextStyle Function(
      BuildContext context,
      TextStyle resolvedStyle,
      Style effectiveAttributes,
      QuillFinalTextStyleRole role,
    );
