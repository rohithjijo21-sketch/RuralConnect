import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel? connectLiveSocket(Uri url, String access) =>
    IOWebSocketChannel.connect(
      url,
      headers: {'Authorization': 'Bearer $access'},
      pingInterval: const Duration(seconds: 20),
    );
