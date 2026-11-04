import 'package:flutter/material.dart';

import '../models_v2.dart';
import 'theme.dart';

/// Operational timeline shared by appointment and job-focused home screens.
/// The parent supplies authorized, real records; this widget never creates metrics.
class WorkQueue extends StatelessWidget {
  const WorkQueue({super.key, required this.title, required this.jobs, required this.onOpen, this.loading = false, this.error, this.onRetry});
  final String title;
  final List<Job> jobs;
  final ValueChanged<Job> onOpen;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TU JORNADA', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 2, color: theme.colorScheme.primary)),
        const SizedBox(height: Gap.sm),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.lg),
        if (loading) const LinearProgressIndicator(semanticsLabel: 'Cargando actividades'),
        if (error != null) ...[
          Text(error!, style: theme.textTheme.bodyMedium),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ] else if (!loading && jobs.isEmpty)
          Text('No hay actividades pendientes en esta vista. Organiza la siguiente desde tu agenda o tus trabajos.', style: theme.textTheme.bodyMedium),
        for (final job in jobs.take(4)) ...[
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 12,
            leading: Container(width: 4, height: 40, decoration: BoxDecoration(color: job.done ? Brand.ok : theme.colorScheme.primary, borderRadius: BorderRadius.circular(4))),
            title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(job.scheduledAt == null ? 'Pendiente de programar' : '${MaterialLocalizations.of(context).formatFullDate(job.scheduledAt!.toLocal())} · ${TimeOfDay.fromDateTime(job.scheduledAt!.toLocal()).format(context)}'),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
            onTap: () => onOpen(job),
          ),
        ],
      ]),
    );
  }
}
