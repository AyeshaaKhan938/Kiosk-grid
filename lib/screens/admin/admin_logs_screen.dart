import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/log_file_util.dart';

/// Admin → View Logs.
///
/// Reads the persistent log files written by LogFileUtil (factory.apk
/// parity port — see `lib/services/log_file_util.dart`) and shows them
/// on-device so an operator standing in front of the kiosk can
/// troubleshoot without USB/adb access.
///
/// Layout:
///   - Top dropdown: choose which day's log file to view (newest first).
///   - Middle: scrollable monospace text view of the file contents.
///   - Bottom: Refresh + Copy path + Close buttons.
///
/// File contents are capped at 256 KB in the native readFile() — older
/// content is trimmed off the head with a truncation marker so the UI
/// never tries to render multi-megabyte blobs.
class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  List<String> _files = const [];
  String? _selectedPath;
  String _content = '';
  bool _loading = true;
  bool _uploading = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFileList();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFileList() async {
    setState(() => _loading = true);
    final files = await LogFileUtil.listFiles();
    setState(() {
      _files = files;
      _selectedPath = files.isNotEmpty ? files.first : null;
    });
    if (_selectedPath != null) {
      await _loadFile(_selectedPath!);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadFile(String path) async {
    setState(() {
      _loading = true;
      _content = '';
    });
    final text = await LogFileUtil.readFile(path);
    if (!mounted) return;
    setState(() {
      _content = text;
      _loading = false;
    });
    // Jump to bottom so the most recent entries are immediately visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _uploadToCloud(String path) async {
    setState(() => _uploading = true);

    // Show indeterminate progress dialog while the multipart POST is in
    // flight. We don't have meaningful byte-level progress for a single
    // POST without instrumenting the http client; spinner is fine.
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF0D1A2B),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  color: Color(0xFF42A5F5), strokeWidth: 2.5),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Uploading log file to vms-cloud…',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );

    final result = await LogFileUtil.uploadFile(path);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress
    await progressDialog;

    setState(() => _uploading = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success
            ? const Color(0xFF388E3C)
            : Colors.redAccent.shade700,
        duration: const Duration(seconds: 5),
        content: Text(
          result.success
              ? 'Uploaded ${result.filename} (${_formatBytes(result.bytes ?? 0)}) — '
                  'check vms-cloud admin → Kiosk Logs.'
              : 'Upload failed: ${result.message}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _copyPath() async {
    if (_selectedPath == null) return;
    await Clipboard.setData(ClipboardData(text: _selectedPath!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Path copied: $_selectedPath'),
        backgroundColor: const Color(0xFF388E3C),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.article_outlined, color: Color(0xFF007ACC), size: 20),
            SizedBox(width: 10),
            Text('View Logs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _selectedPath != null && !_loading
                ? () => _loadFile(_selectedPath!)
                : null,
          ),
          IconButton(
            tooltip: 'Send to vms-cloud',
            icon: const Icon(Icons.cloud_upload_outlined,
                color: Colors.white70),
            onPressed: _selectedPath != null && !_loading && !_uploading
                ? () => _uploadToCloud(_selectedPath!)
                : null,
          ),
          IconButton(
            tooltip: 'Copy path',
            icon: const Icon(Icons.copy_rounded, color: Colors.white70),
            onPressed: _selectedPath != null ? _copyPath : null,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilePicker(),
          const Divider(height: 1, color: Color(0xFF1A2A40)),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0D1A2B),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined,
              color: Color(0xFF007ACC), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: _files.isEmpty
                ? const Text(
                    'No log files yet — log file is created on first event.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                : DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPath,
                    dropdownColor: const Color(0xFF0D1A2B),
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    icon: const Icon(Icons.arrow_drop_down,
                        color: Colors.white70),
                    items: _files
                        .map((path) => DropdownMenuItem(
                              value: path,
                              child: Text(
                                _fileLabel(path),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (path) {
                      if (path == null || path == _selectedPath) return;
                      setState(() => _selectedPath = path);
                      _loadFile(path);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fileLabel(String fullPath) {
    final segs = fullPath.split(RegExp(r'[/\\]'));
    return segs.isEmpty ? fullPath : segs.last;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                  color: Color(0xFF007ACC), strokeWidth: 2.5),
            ),
            SizedBox(height: 14),
            Text('Reading log file…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'No logs have been written yet. The log file is created the '
            'first time something happens (dispense, heartbeat, error, etc.).',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_content.isEmpty) {
      return const Center(
        child: Text(
          'File is empty.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    return Container(
      color: const Color(0xFF060E18),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Scrollbar(
        controller: _scrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          child: SelectableText(
            _content,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.4,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
