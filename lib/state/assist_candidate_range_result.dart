import 'package:harmony/models/pitch.dart';

/// Per-candidate Stage 2 observations (no numeric comfort score).
///
/// Captures user-reported audibility/comfort plus which range points matched.
class AssistCandidateRangeResult {
  AssistCandidateRangeResult(this.shruti);

  /// Candidate Shruti under test.
  final Pitch shruti;

  /// Whether Lower Sa was stably matched.
  bool lowerSaMatched = false;

  /// User reported they could hear and match Lower Sa (`null` until answered).
  bool? lowerSaAudible;

  /// Whether Pa was stably matched.
  bool paMatched = false;

  /// Whether Upper Sa was stably matched.
  bool upperSaMatched = false;

  /// User reported Upper Sa felt comfortable (`null` until answered).
  bool? upperSaComfortable;
}
