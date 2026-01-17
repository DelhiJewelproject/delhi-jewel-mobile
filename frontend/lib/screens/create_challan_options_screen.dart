import 'package:flutter/material.dart';

import 'new_challan_form_screen.dart';
import 'challan_scan_screen.dart';
import 'draft_challans_screen.dart';

class CreateChallanOptionsScreen extends StatelessWidget {
  const CreateChallanOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Challan'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF8F5EF),
              Color(0xFFEFE9DE),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 48 : 20,
              vertical: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Choose how you want to create a challan. Start fresh or pick up older challans for edits.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: Column(
                    children: [
                      _buildMenuButton(
                        context,
                        title: 'New Challan',
                       // subtitle: 'Guided flow with party, station and transport presets',
                        icon: Icons.add_circle_outline_rounded,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NewChallanFormScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildMenuButton(
                        context,
                        title: 'View Old Challans',
                        icon: Icons.drafts_rounded,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DraftChallansScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      // _buildMenuButton(
                      //   context,
                      //   title: 'View Old Challans',
                      //  // subtitle: 'Browse and search all previous challans',
                      //   icon: Icons.history_rounded,
                      //   onTap: () {
                      //     Navigator.push(
                      //       context,
                      //       MaterialPageRoute(
                      //         builder: (context) => const ChallanScanScreen(),
                      //       ),
                      //     );
                      //   },
                      // ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required String title,
   // required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFB8860B).withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB8860B).withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB8860B).withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 28, color: const Color(0xFFB8860B)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    // const SizedBox(height: 6),
                    // Text(
                    //   subtitle,
                    //   style: TextStyle(
                    //     fontSize: 13,
                    //     color: Colors.grey.shade600,
                    //   ),
                    // ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB8860B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}