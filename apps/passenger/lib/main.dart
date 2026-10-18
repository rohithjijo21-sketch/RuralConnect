import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() => runApp(
  const ProviderScope(
    child: RuralConnectApp(
      mode: 'passenger',
      title: 'RuralConnect Passenger',
      color: Color(0xFF13634B),
    ),
  ),
);
