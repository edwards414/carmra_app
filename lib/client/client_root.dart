import 'package:flutter/material.dart';

import 'api_client.dart';
import 'connect_page.dart';
import 'project_list_page.dart';

/// Phone start: reconnect to the last desktop, or pair with a new one.
class ClientRoot extends StatefulWidget {
  const ClientRoot({super.key});

  @override
  State<ClientRoot> createState() => _ClientRootState();
}

class _ClientRootState extends State<ClientRoot> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final saved = await SavedConnection.load();
    Widget next;
    if (saved == null) {
      next = const ConnectPage();
    } else {
      try {
        final client = await ApiClient.connect(saved);
        await SavedConnection.save(saved, client.host);
        next = ProjectListPage(client: client);
      } on ApiException catch (e) {
        next = ConnectPage(saved: saved, initialError: e.message);
      }
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('連線到電腦中…'),
          ],
        ),
      ),
    );
  }
}
