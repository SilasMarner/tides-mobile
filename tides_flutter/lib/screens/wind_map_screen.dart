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

  @override
  void initState() {
    super.initState();
    final uri = Uri.parse(
      'https://embed.windy.com/embed.html'
      '?lat=${widget.lat}&lon=${widget.lon}'
      '&detailLat=${widget.lat}&detailLon=${widget.lon}'
      '&zoom=9&level=surface&overlay=wind'
      '&product=ecmwf&metricWind=mph&metricTemp=%C2%B0F'
      '&message=true&marker=true',
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kNavy)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(uri);
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
            onSelected: (overlay) => _controller.loadRequest(Uri.parse(
              'https://embed.windy.com/embed.html'
              '?lat=${widget.lat}&lon=${widget.lon}'
              '&detailLat=${widget.lat}&detailLon=${widget.lon}'
              '&zoom=9&level=surface&overlay=$overlay'
              '&product=ecmwf&metricWind=mph&metricTemp=%C2%B0F'
              '&message=true&marker=true',
            )),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'wind',
                child: Text('Wind', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'waves',
                child: Text('Waves', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'rain',
                child: Text('Rain', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'temp',
                child: Text('Temperature', style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'clouds',
                child: Text('Clouds', style: TextStyle(color: Colors.white)),
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
