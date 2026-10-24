import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

Future<void> openPrivacyPolicy() async {
  if (Config.privacyUrl.isEmpty) return;
  final uri = Uri.tryParse(Config.privacyUrl);
  if (uri == null || uri.scheme != 'https') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
