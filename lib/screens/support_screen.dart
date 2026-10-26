import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_text.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(appTextValue('تعذر فتح التطبيق المناسب للرابط.', 'Could not open an app for this link.')),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText(ar: 'الدعم والتواصل', en: 'Support and contact')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(
        leading: const Icon(Icons.chat_outlined),
        title: const AppText(ar: 'واتساب', en: 'WhatsApp'),
        subtitle: const Text('+967773436537'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => _open(context, Uri.parse('https://wa.me/967773436537')),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.email_outlined),
        title: const AppText(ar: 'البريد الإلكتروني', en: 'Email'),
        subtitle: const Text('abnalhag2022@gmail.com'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => _open(context, Uri.parse('mailto:abnalhag2022@gmail.com')),
      )),
    ]),
  );
}
