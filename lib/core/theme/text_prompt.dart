import 'package:flutter/material.dart';

class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.message,
    this.label,
    this.maxLength = 50,
  });
  final String title, confirmLabel;
  final String? message, label;
  final int maxLength;
  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) Text(widget.message!),
            if (widget.label != null)
              TextFormField(
                controller: _controller,
                maxLength: widget.maxLength,
                maxLines: widget.maxLength > 100 ? 3 : 1,
                decoration: InputDecoration(labelText: widget.label),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
