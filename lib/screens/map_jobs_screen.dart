import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'job_details_screen.dart';

class MapJobsScreen extends StatefulWidget {
  const MapJobsScreen({super.key});

  @override
  State<MapJobsScreen> createState() => _MapJobsScreenState();
}

class _MapJobsScreenState extends State<MapJobsScreen> {

  final MapController mapController = MapController();

  LatLng center = const LatLng(53.4808, -2.2426); // Manchester

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("Jobs Map"),
      ),

      body: StreamBuilder<QuerySnapshot>(

        stream: FirebaseFirestore.instance.collection('jobs').snapshots(),

        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final jobs = snapshot.data!.docs.map((doc) {

            final data = doc.data() as Map<String, dynamic>;

            return Job.fromFirestore(doc.id, data);

          }).toList();

          final markers = jobs.map((job) {

            return Marker(

              width: 40,
              height: 40,

              point: LatLng(job.lat, job.lng),

              child: GestureDetector(

                onTap: () {

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JobDetailScreen(job: job),
                    ),
                  );

                },

                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 40,
                ),
              ),

            );

          }).toList();

          return Stack(

            children: [

              /// MAP
              FlutterMap(

                mapController: mapController,

                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12,
                ),

                children: [

                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: "builder.jobs.app",
                  ),

                  /// CLUSTER LAYER
                  MarkerClusterLayerWidget(

                    options: MarkerClusterLayerOptions(

                      maxClusterRadius: 45,
                      size: const Size(40, 40),

                      markers: markers,

                      builder: (context, cluster) {

                        return Container(

                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                          ),

                          child: Center(

                            child: Text(
                              cluster.length.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                          ),

                        );

                      },

                    ),
                  ),

                ],
              ),

              /// JOB LIST
              Align(

                alignment: Alignment.bottomCenter,

                child: Container(

                  height: 220,

                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 10,
                        color: Colors.black12,
                      )
                    ],
                  ),

                  child: ListView.builder(

                    scrollDirection: Axis.horizontal,

                    itemCount: jobs.length,

                    itemBuilder: (context, index) {

                      final job = jobs[index];

                      return GestureDetector(

                        onTap: () {

                          mapController.move(
                            LatLng(job.lat, job.lng),
                            14,
                          );

                        },

                        child: Container(

                          width: 220,
                          margin: const EdgeInsets.all(12),

                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              Text(
                                job.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),

                              const SizedBox(height: 6),

                              Text("${job.city} ${job.postcode}"),

                              const Spacer(),

                              Text(
                                "£${job.rate}/h",
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 6),

                              ElevatedButton(

                                onPressed: () {

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          JobDetailScreen(job: job),
                                    ),
                                  );

                                },

                                child: const Text("View"),

                              )

                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )

            ],
          );
        },
      ),
    );
  }
}