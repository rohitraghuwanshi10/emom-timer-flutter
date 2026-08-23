import 'package:flutter/material.dart';

/// Reusable pill-shaped capsule profile selector button for AppBars
class ProfileSelectorCapsule extends StatelessWidget {
  final String currentProfile;
  final List<String> availableProfiles;
  final ValueChanged<String> onProfileSelected;
  final bool isEnabled;

  const ProfileSelectorCapsule({
    super.key,
    required this.currentProfile,
    required this.availableProfiles,
    required this.onProfileSelected,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (availableProfiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Chip(
          avatar: Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.primary),
          label: Text(currentProfile, style: const TextStyle(fontSize: 12)),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: PopupMenuButton<String>(
        enabled: isEnabled,
        onSelected: onProfileSelected,
        itemBuilder: (context) {
          return availableProfiles.map((p) {
            return PopupMenuItem<String>(
              value: p,
              child: Text(p),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.3),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: isEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                currentProfile,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isEnabled ? Colors.white : Colors.grey,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: isEnabled ? Colors.white : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
