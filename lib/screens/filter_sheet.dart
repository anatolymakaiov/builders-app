import 'package:flutter/material.dart';

class FilterResult {
  final String trade;
  final double minRate;
  final double distance;

  FilterResult({
    required this.trade,
    required this.minRate,
    required this.distance,
  });
}

class FilterSheet extends StatefulWidget {

  final FilterResult current;

  const FilterSheet({
    super.key,
    required this.current,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {

  late String trade;
  late double minRate;
  late double distance;

  final searchController = TextEditingController();

  final List<String> allTrades = [

    "All",

    "Bricklayer",
    "Dryliner",
    "Fixer",
    "Carpenter",
    "Joiner",
    "Painter",
    "Decorator",
    "Plumber",
    "Electrician",
    "Groundworker",
    "Labourer",
    "Scaffolder",
    "Tiler",
    "Plasterer",
    "Roofer",
    "Steel Fixer",
    "Welder",

  ];

  List<String> filteredTrades = [];

  @override
  void initState() {
    super.initState();

    trade = widget.current.trade;
    minRate = widget.current.minRate;
    distance = widget.current.distance;

    filteredTrades = allTrades;
  }

  void searchTrade(String text) {

    setState(() {

      if (text.isEmpty) {
        filteredTrades = allTrades;
      } else {

        filteredTrades = allTrades.where((t) {

          return t.toLowerCase().contains(
                text.toLowerCase(),
              );

        }).toList();

      }

    });

  }

  void resetFilters() {

    setState(() {

      trade = "All";
      minRate = 0;
      distance = 50;
      searchController.clear();
      filteredTrades = allTrades;

    });

  }

  @override
  Widget build(BuildContext context) {

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 520,

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// HEADER

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                const Text(
                  "Filters",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                TextButton(
                  onPressed: resetFilters,
                  child: const Text("Reset"),
                )

              ],
            ),

            const SizedBox(height: 20),

            /// TRADE SEARCH

            const Text(
              "Trade",
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: searchController,
              decoration: InputDecoration(

                hintText: "Search trade",

                prefixIcon: const Icon(Icons.search),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),

              ),
              onChanged: searchTrade,
            ),

            const SizedBox(height: 12),

            /// TRADE CHIPS

            SizedBox(
              height: 90,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: filteredTrades.map((t) {

                    final selected = trade == t;

                    return ChoiceChip(

                      label: Text(t),

                      selected: selected,

                      onSelected: (_) {

                        setState(() {
                          trade = t;
                        });

                      },

                    );

                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// RATE

            const Text(
              "Minimum hourly rate",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(
              "£${minRate.toInt()} / hour",
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),

            Slider(
              min: 0,
              max: 50,
              divisions: 25,
              value: minRate,
              onChanged: (v) {

                setState(() {
                  minRate = v;
                });

              },
            ),

            const SizedBox(height: 10),

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
                      minRate: minRate,
                      distance: distance,
                    ),
                  );

                },

                child: const Text("Apply filters"),
              ),
            )

          ],
        ),
      ),
    );
  }
}