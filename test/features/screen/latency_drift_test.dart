import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/features/screen/latency_drift.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Feeds samples every [step] ms from [from] to [to]; position = wall - lag(wall).
bool feed(LatencyDriftMonitor m, {required int from, required int to, int step = 100, required int Function(int wall) lag}) {
  var drifted = false;
  for (var wall = from; wall <= to; wall += step) {
    drifted = m.sample(ms(wall), ms(wall - lag(wall))) || drifted;
  }
  return drifted;
}

void main() {
  test('steady playback at the live edge never drifts', () {
    final m = LatencyDriftMonitor();
    expect(feed(m, from: 0, to: 60000, lag: (_) => 150), isFalse);
  });

  test('lag that grows past 2 s and stays there is reported', () {
    final m = LatencyDriftMonitor();
    expect(feed(m, from: 0, to: 2000, lag: (_) => 100), isFalse);
    // Playback falls behind: lag grows by 0.5 s per second of wall time.
    expect(feed(m, from: 2100, to: 6000, lag: (w) => 100 + (w - 2000) ~/ 2), isFalse); // lag reaches ~2.1 s
    expect(feed(m, from: 6100, to: 10000, lag: (w) => 100 + (w - 2000) ~/ 2), isTrue);
  });

  test('a short lag spike that recovers within the grace period is not reported', () {
    final m = LatencyDriftMonitor();
    feed(m, from: 0, to: 2000, lag: (_) => 100);
    expect(feed(m, from: 2100, to: 3000, lag: (_) => 2500), isFalse);
    expect(feed(m, from: 3100, to: 20000, lag: (_) => 100), isFalse);
  });

  test('a pause in samples (static screen, no frames) re-anchors instead of counting as lag', () {
    final m = LatencyDriftMonitor();
    feed(m, from: 0, to: 2000, lag: (_) => 100);
    // No frames for 10 s; the encoder's timestamps resume where they stopped.
    expect(feed(m, from: 12000, to: 30000, lag: (_) => 10100), isFalse);
  });
}
