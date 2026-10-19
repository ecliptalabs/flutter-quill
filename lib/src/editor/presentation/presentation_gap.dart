import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Immutable vertical presentation space inserted before a rendered document
/// fragment without changing the document itself.
@immutable
class QuillPresentationGap {
  const QuillPresentationGap({
    required this.documentOffset,
    required this.height,
  });

  /// The document offset at which the following rendered fragment starts.
  ///
  /// The offset must identify either a logical line/block start or a physical
  /// soft-line start from a [QuillLayoutSnapshot]. A plan should be regenerated
  /// after document, width, text-scale, or style changes that affect wrapping.
  final int documentOffset;

  /// The vertical space in the editor's logical coordinate system.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is QuillPresentationGap &&
      other.documentOffset == documentOffset &&
      other.height == height;

  @override
  int get hashCode => Object.hash(documentOffset, height);
}

/// An immutable, canonical set of presentation gaps ordered by document
/// offset.
@immutable
class QuillPresentationGapPlan {
  factory QuillPresentationGapPlan(Iterable<QuillPresentationGap> gaps) {
    final ordered = gaps.toList(growable: false)
      ..sort((a, b) => a.documentOffset.compareTo(b.documentOffset));
    int? previousOffset;
    for (final gap in ordered) {
      if (gap.documentOffset < 0) {
        throw ArgumentError.value(
          gap.documentOffset,
          'gaps',
          'Document offsets must be non-negative.',
        );
      }
      if (!gap.height.isFinite || gap.height < 0) {
        throw ArgumentError.value(
          gap.height,
          'gaps',
          'Gap heights must be finite and non-negative.',
        );
      }
      if (previousOffset == gap.documentOffset) {
        throw ArgumentError.value(
          gap.documentOffset,
          'gaps',
          'Duplicate document offsets are not allowed.',
        );
      }
      previousOffset = gap.documentOffset;
    }
    return QuillPresentationGapPlan._(
      ordered.where((gap) => gap.height > 0).toList(growable: false),
    );
  }

  const QuillPresentationGapPlan.empty() : _gaps = const [];

  const QuillPresentationGapPlan._(this._gaps);

  final List<QuillPresentationGap> _gaps;

  UnmodifiableListView<QuillPresentationGap> get gaps =>
      UnmodifiableListView(_gaps);

  bool get isEmpty => _gaps.isEmpty;

  /// Returns the gap immediately before [documentOffset], or zero.
  double gapBefore(int documentOffset) {
    final index = _lowerBound(documentOffset);
    return index < _gaps.length && _gaps[index].documentOffset == documentOffset
        ? _gaps[index].height
        : 0;
  }

  /// Iterates over gaps whose offsets are in `[start, end)`.
  Iterable<QuillPresentationGap> gapsInRange(int start, int end) sync* {
    if (start >= end) return;
    var index = _lowerBound(start);
    while (index < _gaps.length && _gaps[index].documentOffset < end) {
      yield _gaps[index++];
    }
  }

  int _lowerBound(int offset) {
    var low = 0;
    var high = _gaps.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_gaps[mid].documentOffset < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  bool operator ==(Object other) =>
      other is QuillPresentationGapPlan && listEquals(other._gaps, _gaps);

  @override
  int get hashCode => Object.hashAll(_gaps);
}

/// A natural-coordinate boundary and the presentation space before it.
@immutable
class QuillPresentationGapBoundary {
  const QuillPresentationGapBoundary({
    required this.naturalOffset,
    required this.height,
  });

  final double naturalOffset;
  final double height;
}

/// A deterministic transform between natural renderer coordinates and
/// coordinates containing presentation gaps.
///
/// Points inside a gap map back to the natural boundary following the gap.
/// Coordinate lookup is logarithmic in the number of gaps.
@immutable
class QuillPresentationGapTransform {
  factory QuillPresentationGapTransform(
    Iterable<QuillPresentationGapBoundary> boundaries,
  ) {
    final ordered = boundaries.toList(growable: false)
      ..sort((a, b) => a.naturalOffset.compareTo(b.naturalOffset));
    final prefixHeights = <double>[];
    final presentedStarts = <double>[];
    var total = 0.0;
    double? previousOffset;
    for (final boundary in ordered) {
      if (!boundary.naturalOffset.isFinite || boundary.naturalOffset < 0) {
        throw ArgumentError.value(
          boundary.naturalOffset,
          'boundaries',
          'Natural offsets must be finite and non-negative.',
        );
      }
      if (!boundary.height.isFinite || boundary.height <= 0) {
        throw ArgumentError.value(
          boundary.height,
          'boundaries',
          'Gap heights must be finite and positive.',
        );
      }
      if (previousOffset == boundary.naturalOffset) {
        throw ArgumentError.value(
          boundary.naturalOffset,
          'boundaries',
          'Duplicate natural offsets are not allowed.',
        );
      }
      presentedStarts.add(boundary.naturalOffset + total);
      total += boundary.height;
      prefixHeights.add(total);
      previousOffset = boundary.naturalOffset;
    }
    return QuillPresentationGapTransform._(
      ordered,
      prefixHeights,
      presentedStarts,
      total,
    );
  }

  const QuillPresentationGapTransform._(
    this._boundaries,
    this._prefixHeights,
    this._presentedStarts,
    this.totalGapHeight,
  );

  final List<QuillPresentationGapBoundary> _boundaries;
  final List<double> _prefixHeights;
  final List<double> _presentedStarts;

  final double totalGapHeight;

  bool get isEmpty => _boundaries.isEmpty;

  double naturalToPresented(double naturalOffset) =>
      naturalOffset + cumulativeHeightAtNatural(naturalOffset);

  double presentedToNatural(double presentedOffset) {
    final gapIndex = gapIndexAtPresented(presentedOffset);
    if (gapIndex != null) {
      return _boundaries[gapIndex].naturalOffset;
    }
    return presentedOffset - cumulativeHeightAtPresented(presentedOffset);
  }

  double cumulativeHeightAtNatural(double naturalOffset) {
    final count = _upperBoundNatural(naturalOffset);
    return count == 0 ? 0 : _prefixHeights[count - 1];
  }

  double cumulativeHeightBeforeNatural(double naturalOffset) {
    final count = _lowerBoundNatural(naturalOffset);
    return count == 0 ? 0 : _prefixHeights[count - 1];
  }

  double cumulativeHeightAtPresented(double presentedOffset) {
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      final bottom = _presentedStarts[mid] + _boundaries[mid].height;
      if (bottom <= presentedOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low == 0 ? 0 : _prefixHeights[low - 1];
  }

  int? gapIndexAtPresented(double presentedOffset) {
    var low = 0;
    var high = _presentedStarts.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_presentedStarts[mid] <= presentedOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final index = low - 1;
    if (index < 0) return null;
    final start = _presentedStarts[index];
    return presentedOffset < start + _boundaries[index].height ? index : null;
  }

  double presentedGapStart(int index) => _presentedStarts[index];

  QuillPresentationGapBoundary boundaryAt(int index) => _boundaries[index];

  int get length => _boundaries.length;

  int _lowerBoundNatural(double offset) {
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_boundaries[mid].naturalOffset < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  int _upperBoundNatural(double offset) {
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_boundaries[mid].naturalOffset <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

enum QuillLayoutFragmentKind {
  paragraph,
  header,
  listItem,
  blockQuote,
  codeBlock,
  embed,
}

/// Value-only geometry for one rendered physical line.
@immutable
class QuillPhysicalLineGeometry {
  const QuillPhysicalLineGeometry({
    required this.documentRange,
    required this.rect,
  });

  final TextRange documentRange;
  final Rect rect;
}

/// Value-only geometry for one rendered document fragment.
@immutable
class QuillLayoutFragment {
  QuillLayoutFragment({
    required this.documentRange,
    required this.kind,
    required this.rect,
    required List<QuillPhysicalLineGeometry> physicalLines,
    this.embedRect,
  }) : physicalLines = List.unmodifiable(physicalLines);

  final TextRange documentRange;
  final QuillLayoutFragmentKind kind;
  final Rect rect;
  final List<QuillPhysicalLineGeometry> physicalLines;
  final Rect? embedRect;
}

/// Immutable value snapshot of rendered editor geometry.
@immutable
class QuillLayoutSnapshot {
  QuillLayoutSnapshot({
    required this.documentRange,
    required this.editorRect,
    required List<QuillLayoutFragment> fragments,
  }) : fragments = List.unmodifiable(fragments);

  final TextRange documentRange;
  final Rect editorRect;
  final List<QuillLayoutFragment> fragments;
}
