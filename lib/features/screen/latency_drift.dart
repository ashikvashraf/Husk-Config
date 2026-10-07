/// Detects a live H.264 stream whose playback keeps falling behind real time
/// (spec 5.9: fall back to MJPEG when latency drifts past ~2 s).
///
/// Each [sample] pairs the wall-clock time with the player's position. The
/// offset `wall - position` is smallest when playback is at the live edge;
/// lag is how far the current offset sits above that best offset. Lag must
/// stay above [limit] for [sustain] before it counts, so a short hiccup is
/// ignored. A gap of more than [maxGap] between samples (no frames, e.g. a
/// static phone screen) re-anchors the live edge instead of counting as lag.
class LatencyDriftMonitor {
  LatencyDriftMonitor({
    this.limit = const Duration(seconds: 2),
    this.sustain = const Duration(seconds: 3),
    this.maxGap = const Duration(seconds: 1),
  });

  final Duration limit;
  final Duration sustain;
  final Duration maxGap;

  Duration? _best;
  Duration? _lastWall;
  Duration? _laggingSince;

  /// Records one sample; true once the lag has stayed above [limit] for [sustain].
  bool sample(Duration wall, Duration position) {
    final offset = wall - position;
    final best = _best;
    final lastWall = _lastWall;
    _lastWall = wall;
    if (best == null || offset < best || (lastWall != null && wall - lastWall > maxGap)) {
      _best = offset;
      _laggingSince = null;
      return false;
    }
    if (offset - best <= limit) {
      _laggingSince = null;
      return false;
    }
    final since = _laggingSince ??= wall;
    return wall - since >= sustain;
  }
}
