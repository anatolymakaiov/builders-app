import 'package:flutter/material.dart';

class FilterResult {
  final String trade;
  final String jobType;
  final double distance;

  FilterResult({
    required this.trade,
    required this.jobType,
    required this.distance,
  });
}

class FilterSheet extends StatefulWidget {
  final FilterResult current;
  final String title;
  final String actionLabel;
  final bool showDistance;

  const FilterSheet({
    super.key,
    required this.current,
    this.title = "Filters",
    this.actionLabel = "Apply filters",
    this.showDistance = false,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late String trade;
  late String jobType;
  late double distance;

  final List<String> trades = [
    "All",
    "Bricklayer",
    "Dryliner",
    "Carpenter",
    "Joiner",
    "Painter",
    "Decorator",
    "Plasterer",
    "Tiler",
    "Floor layer",
    "Groundworker",
    "Steel fixer",
    "Concrete finisher",
    "Scaffolder",
    "Roofer",
    "Window fitter",
    "Door installer",
    "Electrician",
    "Electrical mate",
    "Plumber",
    "Pipe fitter",
    "Gas engineer",
    "HVAC engineer",
    "Fire alarm engineer",
    "Security engineer",
    "Data engineer",
    "Kitchen fitter",
    "Bathroom fitter",
    "Handyman",
    "Snagger",
    "Cleaner",
    "Labourer",
  ];

  @override
  void initState() {
    super.initState();

    trade = widget.current.trade;
    jobType = widget.current.jobType;
    distance = widget.current.distance;
  }

  void resetFilters() {
    setState(() {
      trade = "All";
      jobType = "All";
      distance = 50;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        height: widget.showDistance ? 520 : 390,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                OutlinedButton(
                  onPressed: resetFilters,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black87,
                  ),
                  child: const Text("Reset"),
                )
              ],
            ),

            const SizedBox(height: 20),

            /// TRADE

            const Text(
              "Trade",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              initialValue: trades.contains(trade) ? trade : "All",
              items: trades
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  trade = value;
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            /// JOB TYPE

            const Text(
              "Work format",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              initialValue: jobType,
              items: const [
                DropdownMenuItem(value: "All", child: Text("All")),
                DropdownMenuItem(value: "hourly", child: Text("Daywork")),
                DropdownMenuItem(value: "price", child: Text("Price")),
                DropdownMenuItem(
                  value: "negotiable",
                  child: Text("Negotiable"),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  jobType = value;
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            if (widget.showDistance) ...[
              /// DISTANCE

              const Text(
                "Distance",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "${distance.toInt()} miles",
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),

              Slider(
                min: 5,
                max: 50,
                divisions: 9,
                value: distance,
                onChanged: (v) {
                  setState(() {
                    distance = v;
                  });
                },
              ),
            ],

            const Spacer(),

            /// APPLY BUTTON

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    FilterResult(
                      trade: trade,
                      jobType: jobType,
                      distance: distance,
                    ),
                  );
                },
                child: Text(widget.actionLabel),
              ),
            )
          ],
        ),
      ),
    );
  }
}
