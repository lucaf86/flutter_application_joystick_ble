import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebConfigPage extends StatefulWidget {
  final String url;
  const WebConfigPage({super.key, required this.url});

  @override
  State<WebConfigPage> createState() => _WebConfigPageState();
}

class _WebConfigPageState extends State<WebConfigPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF0F2F5))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configurazione Parametri ESP32", style: TextStyle(color: Colors.black, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context), 
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
