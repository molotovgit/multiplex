import 'package:flutter/material.dart';

import '../../sessions/session_manager.dart';

/// Remote file browser (SFTP) for one live session.
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key, required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Files on ${session.host.title}')));
}
