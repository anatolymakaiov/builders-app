import 'package:flutter/material.dart';

enum PortraitWebSection {
  jobs('Jobs', Icons.work_outline),
  map('Map', Icons.map_outlined),
  applications('Applications', Icons.assignment_outlined),
  chats('Chats', Icons.chat_bubble_outline),
  profile('Profile', Icons.person_outline);

  const PortraitWebSection(this.label, this.icon);

  final String label;
  final IconData icon;
}
