import 'package:flutter/material.dart';

import '../core/api/husk_exception.dart';
import '../core/api/text_result.dart';

/// Runs a device command and reports the outcome in a SnackBar. `ERR …`
/// replies and thrown errors use the error colour; [hint] may add advice for
/// a specific reply. Returns the reply, or null when the call failed.
Future<TextResult?> runCommand(
  BuildContext context,
  Future<TextResult> Function() action, {
  String? success,
  String? Function(String reply)? hint,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    final result = await action();
    final extra = hint?.call(result.text);
    final text = result.isErr ? result.text : (success ?? (result.text.isEmpty ? 'Done' : result.text));
    messenger.showSnackBar(SnackBar(
      content: Text(extra == null ? text : '$text\n$extra'),
      backgroundColor: result.isErr ? errorColor : null,
    ));
    return result;
  } on HuskException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: errorColor));
    return null;
  }
}
