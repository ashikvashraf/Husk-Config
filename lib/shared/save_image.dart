import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Desktop: native save dialog. Mobile: share sheet (Save to Photos/Files…).
Future<void> saveImage(BuildContext context, Uint8List bytes, String fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final file = XFile.fromData(bytes, mimeType: 'image/jpeg', name: fileName);
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(
        files: [file],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      return;
    }
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [XTypeGroup(label: 'JPEG image', extensions: ['jpg', 'jpeg'])],
    );
    if (location == null) return;
    await file.saveTo(location.path);
    messenger.showSnackBar(SnackBar(content: Text('Saved to ${location.path}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save the image: $e')));
  }
}
