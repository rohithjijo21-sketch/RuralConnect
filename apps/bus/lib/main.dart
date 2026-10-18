import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';

void main() => runApp(
  const ProviderScope(
    child: RuralConnectApp(
      mode: 'bus',
      title: 'RuralConnect Bus',
      color: Color(0xFF8A4D12),
    ),
  ),
);
