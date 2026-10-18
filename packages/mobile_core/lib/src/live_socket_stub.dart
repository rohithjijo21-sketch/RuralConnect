import 'package:web_socket_channel/web_socket_channel.dart';

// Browsers cannot set the Authorization header on a WebSocket handshake.
// Retain authenticated HTTP polling rather than putting tokens in URLs.
WebSocketChannel? connectLiveSocket(Uri url, String access) => null;
