import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models/tools_models.dart';
import '../servers/api_provider.dart';

final motionProvider = FutureProvider.autoDispose.family<MotionConfig, String>((ref, id) => ref.watch(apiProvider(id)).motion());

final eventsProvider = FutureProvider.autoDispose.family<List<MotionEvent>, String>((ref, id) => ref.watch(apiProvider(id)).events());

/// True once the user accepted the raw-command warning in this app session.
class RpcConfirmed extends Notifier<bool> {
  @override
  bool build() => false;

  void confirm() => state = true;
}

final rpcConfirmedProvider = NotifierProvider<RpcConfirmed, bool>(RpcConfirmed.new);
