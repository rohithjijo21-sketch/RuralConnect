import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruralconnect_mobile/ruralconnect_mobile.dart';
void main() => runApp(const ProviderScope(child: RuralConnectApp(mode: 'driver', title: 'RuralConnect Driver', color: Color(0xFF244E89))));
