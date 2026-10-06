import 'package:flutter/material.dart';
import '../../../services/worker_assignment_service.dart';

class WebWorkerAssignments extends StatelessWidget {
  const WebWorkerAssignments({super.key, required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WorkerAssignment>>(
        stream: WorkerAssignmentService().watchOwn(workerId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }
          final current = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Current / next work',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              for (final doc in current)
                Card(
                    child: ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: Text(doc.siteName),
                  subtitle: Text([
                    doc.employerName,
                    doc.tradeName,
                    _date(doc.startDate),
                    _date(doc.expectedEndDate),
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' • ')),
                  trailing: Text(doc.status),
                )),
            ]),
          );
        },
      );

  String? _date(DateTime? date) {
    if (date == null) return null;
    return '${date.day}/${date.month}/${date.year}';
  }
}
