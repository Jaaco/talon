// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:uuid/uuid.dart';

String getOrCreateWebClientId(Uuid uuid) {
  const key = 'talon_client_id';
  final existing = html.window.sessionStorage[key];
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }
  final newId = uuid.v4();
  html.window.sessionStorage[key] = newId;
  return newId;
}
