import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/husk_api.dart';

/// Husk's own /control (MJPEG) or /controlhw (H.264) page in a WebView.
/// The page is loaded from the phone's IP, so Husk's same-site checks pass.
class WebControlView extends StatefulWidget {
  const WebControlView({super.key, required this.api});

  final HuskApi api;

  @override
  State<WebControlView> createState() => _WebControlViewState();
}

class _WebControlViewState extends State<WebControlView> {
  bool _hardware = false;
  String? _error;
  bool? _webViewAvailable;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      WebViewEnvironment.getAvailableVersion().then((version) {
        if (mounted) setState(() => _webViewAvailable = version != null);
      });
    } else {
      _webViewAvailable = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_webViewAvailable) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case false:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Web control needs the Microsoft Edge WebView2 runtime.'),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/')),
              child: const Text('Get WebView2'),
            ),
          ]),
        );
      case true:
        break;
    }
    final url = widget.api.uri(_hardware ? '/controlhw' : '/control').toString();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('MJPEG page')),
            ButtonSegment(value: true, label: Text('H.264 page')),
          ],
          selected: {_hardware},
          onSelectionChanged: (v) => setState(() {
            _hardware = v.first;
            _error = null;
          }),
        ),
      ),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Expanded(
        child: InAppWebView(
          key: ValueKey(url),
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: InAppWebViewSettings(mediaPlaybackRequiresUserGesture: false, allowsInlineMediaPlayback: true),
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame != false && mounted) {
              setState(() => _error = 'Could not load the control page: ${error.description}');
            }
          },
        ),
      ),
    ]);
  }
}
