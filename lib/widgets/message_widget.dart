import 'package:flutter/material.dart';

class _Message extends StatelessWidget {

  final String text;

  const _Message(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(text),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Center(child: Text("OK")),
        ),
      ],
    );
  }
}

void displayMessage(BuildContext context, String? text) {
  if(text != null && text.isNotEmpty) {
    showDialog(
      context: context,
      builder: (_) => _Message(text),
    );
  }
}
