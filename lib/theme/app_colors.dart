import 'package:flutter/material.dart';

class AppColors {
  static const deep = Color(0xFF031722);
  static const navy = Color(0xFF062D41);
  static const navy2 = Color(0xFF083B55);
  static const blueprint = Color(0xFF0D4E70);
  static const blueprintLine = Color(0xFF7DB9D8);
  static const glow = Color(0xFF8BD4FF);
  static const ink = Color(0xFF123238);
  static const muted = Color(0xFF5C7180);
  static const canvas = Color(0xFFFAFCFB);
  static const surface = Color(0xFFF7FAF8);
  static const surfaceAlt = Color(0xFFEFF6F8);
  static const green = Color(0xFF7DB9D8);
  static const greenDark = Color(0xFF2F6E92);
  static const success = Color(0xFF55B879);
  static const warning = Color(0xFFEAAE4A);
  static const danger = Color(0xFFF04465);
  static const purple = Color(0xFF8D6DDF);

  static Color status(String value) {
    switch (value.toLowerCase().trim()) {
      case "active":
      case "approved":
      case "offer_accepted":
      case "accepted":
      case "hired":
      case "paid":
        return success;
      case "offer_sent":
      case "pending":
      case "pending_review":
      case "in_review":
        return blueprintLine;
      case "negotiation":
        return purple;
      case "rejected":
      case "offer_rejected":
      case "failed":
      case "expired":
      case "cancelled":
        return danger;
      case "paused":
      case "inactive":
      case "offer_withdrawn":
        return warning;
      default:
        return greenDark;
    }
  }
}

class AppAssets {
  static const logo = "assets/branding/stroyka_logo.svg";

  static const darkBackgrounds = [
    "assets/branding/app_bg_cranes_yard.png",
    "assets/branding/app_bg_workers_city.png",
    "assets/branding/app_bg_forklift_site.png",
    "assets/branding/app_bg_highrise_sunset.png",
  ];

  static const lightTextures = [
    "assets/branding/texture_light_triangles.jpg",
    "assets/branding/texture_light_cloud.jpg",
    "assets/branding/texture_light_dots.jpg",
  ];
}
