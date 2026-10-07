import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/storage/app_settings.dart';

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// How often live data refreshes: null while the app is in the background,
/// Duration.zero when polling is off (fetch once), otherwise the interval.
final pollIntervalProvider = Provider<Duration?>((ref) {
  if (!ref.watch(appForegroundProvider)) return null;
  return Duration(seconds: ref.watch(settingsProvider.select((s) => s.pollIntervalSeconds)));
});
