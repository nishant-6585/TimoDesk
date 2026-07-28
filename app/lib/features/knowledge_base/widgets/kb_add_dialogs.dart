import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../providers/kb_provider.dart';

/// Dialogs for the two new ingestion routes: document upload (PDF / Word /
/// text) and whole-site crawl. Style mirrors the existing _AddTextDialog.

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: MikeeColors.inset,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MikeeColors.border)),
    );

List<Widget> _dialogActions({
  required bool busy,
  required BuildContext context,
  required VoidCallback onSave,
  required String saveLabel,
}) {
  return [
    TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel')),
    ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: MikeeColors.primary, foregroundColor: Colors.white),
      onPressed: busy ? null : onSave,
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(saveLabel),
    ),
  ];
}

/// Pick a PDF / Word / text document and ingest it into the KB.
class KbAddFileDialog extends StatefulWidget {
  const KbAddFileDialog({Key? key}) : super(key: key);

  @override
  State<KbAddFileDialog> createState() => _KbAddFileDialogState();
}

class _KbAddFileDialogState extends State<KbAddFileDialog> {
  final _topic = TextEditingController();
  PlatformFile? _file;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
      withData: true, // bytes in memory — required on web
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _file = result.files.first;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null || f.bytes == null) {
      setState(() => _error = 'Pick a document first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await kbIngestFile(f.name, f.bytes!, topic: _topic.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: const Text('Add a document', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: _busy ? null : _pick,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MikeeColors.inset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: f == null ? MikeeColors.border : MikeeColors.primary),
              ),
              child: Column(children: [
                Icon(f == null ? Icons.upload_file : Icons.description,
                    color: f == null ? Colors.white38 : MikeeColors.primary, size: 32),
                const SizedBox(height: 8),
                Text(
                  f == null
                      ? 'Click to choose a file — PDF, Word (.docx), .txt or .md'
                      : '${f.name}  ·  ${(f.size / 1024).toStringAsFixed(0)} KB',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: f == null ? Colors.white38 : Colors.white, fontSize: 13),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Topic (optional) — e.g. Company profile'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: MikeeColors.error, fontSize: 12)),
            ),
        ]),
      ),
      actions: _dialogActions(
          busy: _busy, context: context, onSave: _save, saveLabel: 'Extract & add'),
    );
  }
}

/// Start a same-origin website crawl (BFS from a seed URL, page-capped).
class KbCrawlDialog extends StatefulWidget {
  const KbCrawlDialog({Key? key}) : super(key: key);

  @override
  State<KbCrawlDialog> createState() => _KbCrawlDialogState();
}

class _KbCrawlDialogState extends State<KbCrawlDialog> {
  final _url = TextEditingController();
  final _topic = TextEditingController();
  double _maxPages = 10;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await kbCrawlStart(_url.text.trim(),
          maxPages: _maxPages.round(), topic: _topic.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MikeeColors.cardTop,
      title: const Text('Crawl a website', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _url,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('https://… (start page — same-site links are followed)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Topic (optional)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Max pages',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            Expanded(
              child: Slider(
                value: _maxPages,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: MikeeColors.primary,
                label: '${_maxPages.round()}',
                onChanged: _busy ? null : (v) => setState(() => _maxPages = v),
              ),
            ),
            Text('${_maxPages.round()}',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Runs in the background — progress appears on this screen. '
              'JS-rendered sites won\'t crawl well; paste those as text.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: MikeeColors.error, fontSize: 12)),
            ),
        ]),
      ),
      actions: _dialogActions(
          busy: _busy, context: context, onSave: _save, saveLabel: 'Start crawl'),
    );
  }
}
