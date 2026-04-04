// =============================================================================
// Frame classification by structural signature.
//
// Incoming AB02 frames are classified by bytes[2..5] (4 bytes after AA 55).
// These bytes appear to be structurally stable across a repeating frame type
// while bytes[6..] carry telemetry values that vary continuously.
//
// Categories are auto-assigned labels: Frame-A, Frame-B, Frame-C, …
// =============================================================================

/// A recognised frame category with its key and auto-assigned label.
class FrameCategory {
  /// The 4-byte structural key: hex of bytes[2..5], e.g. "01 02 00 00".
  final String key;

  /// Auto-assigned label: "Frame-A", "Frame-B", …
  final String label;

  /// How many times this frame type has been seen (cumulative).
  int count;

  FrameCategory({required this.key, required this.label, this.count = 0});
}

/// Classifies RX frames into structural categories and tracks counts.
class FrameClassifier {
  final _categories = <String, FrameCategory>{}; // key → category
  final _labelNames = <String>[]; // ordered labels for assignment

  static const _labelAlphabet = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
  ];

  /// All known categories, ordered by first-seen time.
  List<FrameCategory> get categories => List.unmodifiable(_categories.values);

  // -- Mutating methods (call once per incoming frame) -------------------------

  /// Classify [hexFrame] (space-separated hex string), increment count, and
  /// return the [FrameCategory].  Creates a new category on first encounter.
  ///
  /// [hexFrame] must be the full frame hex — e.g. "AA 55 01 02 …".
  /// Returns null if the frame is too short or doesn't have AA 55 header.
  FrameCategory? classify(String hexFrame) {
    final key = _extractKey(hexFrame);
    if (key == null) return null;

    if (_categories.containsKey(key)) {
      _categories[key]!.count++;
      return _categories[key];
    }

    // New category — assign next label.
    final idx = _categories.length;
    final labelName = idx < _labelAlphabet.length
        ? 'Frame-${_labelAlphabet[idx]}'
        : 'Frame-${idx + 1}';

    final cat = FrameCategory(key: key, label: labelName, count: 1);
    _categories[key] = cat;
    _labelNames.add(labelName);
    return cat;
  }

  // -- Lookup-only methods (safe to call multiple times on same data) ----------

  /// Returns the label for [hexFrame] without mutating counts.
  /// Returns null if the key is not yet known.
  String? labelForHex(String hexFrame) {
    final key = _extractKey(hexFrame);
    return key == null ? null : _categories[key]?.label;
  }

  /// Returns the set of unique category labels present in [hexFrames].
  Set<String> labelsIn(List<String> hexFrames) {
    final result = <String>{};
    for (final hex in hexFrames) {
      final label = labelForHex(hex);
      if (label != null) result.add(label);
    }
    return result;
  }

  /// Returns how many frames in [hexFrames] match each known category.
  Map<String, int> countIn(List<String> hexFrames) {
    final result = <String, int>{};
    for (final hex in hexFrames) {
      final label = labelForHex(hex);
      if (label != null) result[label] = (result[label] ?? 0) + 1;
    }
    return result;
  }

  /// One-liner summary of all categories, e.g. "Frame-A(12) Frame-B(3)".
  String summary() => _categories.values
      .map((c) => '${c.label}(${c.count})')
      .join('  ');

  /// Resets all categories and counts.
  void reset() {
    _categories.clear();
    _labelNames.clear();
  }

  // -- Private -----------------------------------------------------------------

  /// Extracts the 4-byte structural key from bytes[2..5] of [hexFrame].
  /// Returns null if the frame is malformed.
  static String? _extractKey(String hexFrame) {
    final parts = hexFrame.trim().split(RegExp(r'\s+'));
    if (parts.length < 6) return null;
    if (parts[0].toUpperCase() != 'AA' || parts[1].toUpperCase() != '55') {
      return null;
    }
    return '${parts[2]} ${parts[3]} ${parts[4]} ${parts[5]}'.toUpperCase();
  }
}

// -- Free functions ------------------------------------------------------------

/// Returns a human-readable diff summary of frame labels seen before and after
/// a TX event.
///
/// [typesBefore] — set of category labels observed in the pre-TX window.
/// [typesAfter]  — set of category labels observed in the post-TX window.
String frameDiffSummary({
  required Set<String> typesBefore,
  required Set<String> typesAfter,
}) {
  final appeared = typesAfter.difference(typesBefore);
  final disappeared = typesBefore.difference(typesAfter);
  final common = typesBefore.intersection(typesAfter);

  final lines = <String>[];
  if (appeared.isNotEmpty) lines.add('NEW after TX: ${appeared.join(', ')}');
  if (disappeared.isNotEmpty) lines.add('GONE after TX: ${disappeared.join(', ')}');
  if (common.isNotEmpty) lines.add('unchanged: ${common.join(', ')}');
  if (lines.isEmpty) return 'no frame-type change detected';
  return lines.join('\n');
}
