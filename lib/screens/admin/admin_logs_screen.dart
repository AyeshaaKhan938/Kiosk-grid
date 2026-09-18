import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/log_file_util.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';

/// Admin → View Logs — on-device kiosk log files.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _uploadToCloud(String path) async {
    setState(() => _uploading = true);

    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdminTheme.withLightTheme(
        child: const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Uploading log file to vms-cloud…',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final result = await LogFileUtil.uploadFile(path);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await progressDialog;

    setState(() => _uploading = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Uploaded ${result.filename} (${_formatBytes(result.bytes ?? 0)})'
              : 'Upload failed: ${result.message}',
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _copyPath() async {
    if (_selectedPath == null) return;
    await Clipboard.setData(ClipboardData(text: _selectedPath!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Path copied: $_selectedPath')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Kiosk logs',
      subtitle: 'On-device troubleshooting',
      leading: AdminPageScaffold.backLeading(context),
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          _buildFilePicker(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: AdminColors.card,
      child: Row(
        children: [
          const Icon(Icons.folder_outlined,
              color: AdminColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: _files.isEmpty
                ? const Text(
                    'No log files yet — created on first event.',
                    style: TextStyle(
                      color: AdminColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                : DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPath,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      color: AdminColors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    items: _files
                        .map(
                          (path) => DropdownMenuItem(
                            value: path,
                            child: Text(
                              _fileLabel(path),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (path) {
                      if (path == null || path == _selectedPath) return;
                      setState(() => _selectedPath = path);
                      _loadFile(path);
                    },
                  ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _selectedPath != null && !_loading
                ? () => _loadFile(_selectedPath!)
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Send to vms-cloud',
            onPressed: _selectedPath != null && !_loading && !_uploading
                ? () => _uploadToCloud(_selectedPath!)
                : null,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Copy path',
            onPressed: _selectedPath != null ? _copyPath : null,
            icon: const Icon(Icons.copy_rounded),
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
            CircularProgressIndicator(color: AdminColors.accent),
            SizedBox(height: 14),
            Text(
              'Reading log file…',
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'No logs yet. Files appear after dispense, heartbeat, or errors.',
            style: TextStyle(
              color: AdminColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_content.isEmpty) {
      return const Center(
        child: Text(
          'File is empty.',
          style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: AdminSurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: SelectableText(
              _content,
              style: const TextStyle(
                color: AdminColors.textPrimary,
                fontSize: 11,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
