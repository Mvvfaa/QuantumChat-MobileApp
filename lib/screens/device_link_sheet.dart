import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';

/// Host-side device linking: show QR for another device to scan.
/// Camera scanner for becoming a secondary is skipped to avoid NDK-heavy deps.
class DeviceLinkSheet extends StatefulWidget {
  const DeviceLinkSheet({super.key});

  @override
  State<DeviceLinkSheet> createState() => _DeviceLinkSheetState();
}

class _DeviceLinkSheetState extends State<DeviceLinkSheet> {
  bool loading = true;
  String? error;
  String? linkId;
  String? token;
  String? expiresAt;
  String statusText = 'Preparing pairing…';
  Map<String, dynamic>? pendingRequest;
  bool busy = false;

  void _onLinkRequest(dynamic data) {
    if (!mounted) return;
    if (data is Map) {
      setState(() {
        pendingRequest = Map<String, dynamic>.from(data);
        statusText = 'A new device is waiting for approval.';
      });
    }
  }

  void _onLinked(dynamic data) {
    if (!mounted) return;
    setState(() {
      statusText = 'Device linked successfully.';
      pendingRequest = null;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    try {
      final socket = context.read<ChatController>().socket;
      socket.off('device:link-request', _onLinkRequest);
      socket.off('device:linked', _onLinked);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _start() async {
    final auth = context.read<AuthController>();
    final socket = context.read<ChatController>().socket;
    socket.on('device:link-request', _onLinkRequest);
    socket.on('device:linked', _onLinked);

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await auth.api.createDeviceLinkRequest();
      if (!mounted) return;
      setState(() {
        linkId = data['linkId']?.toString();
        token = data['token']?.toString();
        expiresAt = data['expiresAt']?.toString();
        statusText = 'Scan this QR on the new device (web Link Device page).';
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  String get _qrPayload {
    if (linkId == null || token == null) return '';
    return jsonEncode({'linkId': linkId, 'token': token, 'v': 1});
  }

  Future<void> _approve() async {
    final id = pendingRequest?['linkId']?.toString() ?? linkId;
    if (id == null) return;
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.approveDeviceLink(id);
      if (!mounted) return;
      setState(() {
        statusText = 'Device linked successfully.';
        pendingRequest = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reject() async {
    final id = pendingRequest?['linkId']?.toString();
    if (id == null) return;
    setState(() => busy = true);
    try {
      await context.read<AuthController>().api.rejectDeviceLink(id);
      if (!mounted) return;
      setState(() {
        statusText = 'Link request rejected.';
        pendingRequest = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Link a device', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(statusText, textAlign: TextAlign.center, style: TextStyle(color: colors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (error != null)
              Text(error!, style: TextStyle(color: colors.error))
            else if (_qrPayload.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(
                  data: _qrPayload,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 8),
                Text('Expires: $expiresAt', style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ],
            if (pendingRequest != null) ...[
              const SizedBox(height: 16),
              Text(
                'Approve ${pendingRequest!['deviceLabel'] ?? 'new device'}?',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : _reject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : _approve,
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
