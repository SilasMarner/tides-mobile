import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme.dart';

class WindMapScreen extends StatefulWidget {
  final double lat;
  final double lon;
  final String stationName;

  const WindMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.stationName,
  });

  @override
  State<WindMapScreen> createState() => _WindMapScreenState();
}

class _WindMapScreenState extends State<WindMapScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String _overlay = 'wind';

  String _buildUrl(String overlay) =>
      'https://embed.windy.com/embed2.html'
      '?lat=${widget.lat}&lon=${widget.lon}'
      '&zoom=8&level=surface&overlay=$overlay'
      '&product=ecmwf&metricWind=mph&metricTemp=%C2%B0F'
      '&marker=true&pressure=true&calendar=now'
      '&message=true&type=map&location=coordinates';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kNavy)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(_buildUrl(_overlay)));
  }

  void _switchOverlay(String overlay) {
    setState(() {
      _loading = true;
      _overlay = overlay;
    });
    _controller.loadRequest(Uri.parse(_buildUrl(overlay)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.stationName.toUpperCase()} — WIND MAP',
          style: const TextStyle(color: kCyan, fontSize: 14),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers, color: kCyan),
            tooltip: 'Overlay',
            color: kNavyLight,
            onSelected: _switchOverlay,
            itemBuilder: (_) => [
              for (final item in const [
                ('wind',    'Wind'),
                ('waves',   'Waves'),
                ('swell',   'Swell'),
                ('rain',    'Rain / Thunder'),
                ('temp',    'Temperature'),
                ('pressure','Pressure'),
                ('clouds',  'Clouds'),
              ])
                PopupMenuItem(
                  value: item.$1,
                  child: Row(children: [
                    if (_overlay == item.$1)
                      const Icon(Icons.check, size: 16, color: kCyan)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(item.$2,
                        style: TextStyle(
                            color: _overlay == item.$1
                                ? kCyan
                                : Colors.white)),
                  ]),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: kCyan)),
        ],
      ),
    );
  }
}
