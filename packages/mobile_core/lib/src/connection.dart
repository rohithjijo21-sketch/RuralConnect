import 'package:flutter/material.dart';
import 'api.dart';
import 'demo.dart';

class ConnectionGate extends StatefulWidget {
  final Api api;
  final String title, mode;
  final Widget Function(Api api, VoidCallback connectionSettings) builder;
  const ConnectionGate({
    super.key,
    required this.api,
    required this.title,
    required this.mode,
    required this.builder,
  });
  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  final url = TextEditingController();
  bool loading = true, busy = false, connected = false;
  String? error;
  DemoApi? demo;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      await widget.api.restore();
    } catch (_) {
      /* No native storage in a widget preview; setup stays available. */
    }
    if (!mounted) return;
    setState(() {
      url.text = widget.api.dio.options.baseUrl;
      connected = widget.api.endpointConfirmed;
      loading = false;
    });
  }

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.connect(url.text);
      if (mounted) {
        setState(() {
          connected = true;
          demo = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void settings() {
    setState(() {
      connected = false;
      demo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (demo != null) return widget.builder(demo!, settings);
    if (connected) return widget.builder(widget.api, settings);
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.route_rounded,
                    size: 56,
                    color: Color(0xFF126A50),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: palette.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Connect to your test server',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: palette.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Keep your phone and computer on the same Wi-Fi. Enter the address shown by the RuralConnect test server.',
                    style: TextStyle(color: palette.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server address',
                      hintText: 'http://192.168.1.10:3001/v1',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The connection is checked before sign-in. Changing servers signs you out. Use HTTPS outside your private test network.',
                    style: TextStyle(
                      color: palette.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(error!, style: TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : connect,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF126A50),
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: Text(
                      busy ? 'Checking server…' : 'Connect and continue',
                    ),
                  ),
                  if (widget.mode == 'passenger') ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => demo = DemoApi()),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text('Explore passenger UI demo'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Demo uses labelled sample schedules. It cannot make bookings, payments or track real vehicles.',
                      style: TextStyle(
                        color: palette.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
