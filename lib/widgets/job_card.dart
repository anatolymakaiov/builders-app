import 'package:flutter/material.dart';
import '../models/job.dart';
import '../screens/job_details_screen.dart';

class JobCard extends StatelessWidget {
  final Job job;

  const JobCard({super.key, required this.job});

  IconData _iconForJob(String title) {
    final t = title.toLowerCase();

    if (t.contains("electric")) return Icons.flash_on;
    if (t.contains("plumb")) return Icons.plumbing;
    if (t.contains("builder") || t.contains("construction")) return Icons.construction;
    if (t.contains("carpent")) return Icons.handyman;

    return Icons.work;
  }

  Color _colorForJob(String title) {
    final t = title.toLowerCase();

    if (t.contains("electric")) return Colors.amber;
    if (t.contains("plumb")) return Colors.blue;
    if (t.contains("builder")) return Colors.orange;
    if (t.contains("carpent")) return Colors.brown;

    return Colors.grey;
  }

  String rateText() {
    if (job.jobType == "negotiable") {
      return "Negotiable";
    }

    if (job.jobType == "price") {
      return "£${job.rate.toInt()}";
    }

    return "£${job.rate.toInt()}/h";
  }

  @override
  Widget build(BuildContext context) {
    final icon = _iconForJob(job.title);
    final color = _colorForJob(job.title);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => JobDetailScreen(job: job),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [

                /// JOB ICON
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 16),

                /// JOB INFO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        job.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            job.location,
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),

                    ],
                  ),
                ),

                /// RATE BADGE
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    rateText(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}