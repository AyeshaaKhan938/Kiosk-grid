import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/machine_issue_component.dart';

/// Reports machine hardware / subsystem issues to VMFS Cloud.
final class MachineIssueReporter {
  MachineIssueReporter({
    required this.baseUrl,
    required this.deviceToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String deviceToken;
  final http.Client _client;

  final List<Map<String, dynamic>> _offlineQueue = [];

  Future<void> report({
    required MachineIssueComponent component,
    MachineIssueSeverity severity = MachineIssueSeverity.critical,
    String? code,
    String? title,
    String? message,
    int? slotNumber,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = {
      'component': component.apiValue,
      'severity': severity.apiValue,
      if (code != null) 'code': code,
      if (title != null) 'title': title,
      if (message != null) 'message': message,
      if (slotNumber != null) 'slot_number': slotNumber,
      if (metadata != null) 'metadata': metadata,
    };

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/v1/kiosk/issues'),
        headers: _headers(),
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await flushOfflineQueue();

        return;
      }

      _offlineQueue.add({...payload, 'resolved': false});
    } catch (_) {
      _offlineQueue.add({...payload, 'resolved': false});
    }
  }

  Future<void> resolve({
    required MachineIssueComponent component,
    String? code,
    int? slotNumber,
  }) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/api/v1/kiosk/issues/resolve'),
        headers: _headers(),
        body: jsonEncode({
          'component': component.apiValue,
          if (code != null) 'code': code,
          if (slotNumber != null) 'slot_number': slotNumber,
        }),
      );
    } catch (_) {
      _offlineQueue.add({
        'component': component.apiValue,
        if (code != null) 'code': code,
        if (slotNumber != null) 'slot_number': slotNumber,
        'resolved': true,
      });
    }
  }

  Future<void> flushOfflineQueue() async {
    if (_offlineQueue.isEmpty) {
      return;
    }

    final batch = List<Map<String, dynamic>>.from(_offlineQueue);

    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/kiosk/issues/batch'),
      headers: _headers(),
      body: jsonEncode({'issues': batch}),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _offlineQueue.clear();
    }
  }

  Map<String, String> _headers() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $deviceToken',
      };
}
