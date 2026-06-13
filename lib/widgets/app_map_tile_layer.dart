import 'package:flutter_map/flutter_map.dart';

TileLayer buildBaseTileLayer() {
  return TileLayer(
    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    fallbackUrl: "https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png",
    userAgentPackageName: "builder.jobs.app",
  );
}
