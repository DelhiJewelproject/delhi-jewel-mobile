import 'package:flutter/material.dart';
import 'view_screen.dart';
import 'order_form_screen.dart';
import 'qr_test_screen.dart';
import 'label_screen.dart';
import 'create_challan_options_screen.dart';
//import 'challan_main_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isSmallScreen = screenSize.width < 360;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFFFFF),
              const Color(0xFFF8F8F8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Compact Header Section
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isSmallScreen ? 20 : isTablet ? 32 : 24,
                  isSmallScreen ? 16 : 20,
                  isSmallScreen ? 20 : isTablet ? 32 : 24,
                  isSmallScreen ? 16 : 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DecoJewels',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 24 : isTablet ? 32 : 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A1A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        Text(
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            color: const Color(0xFF666666),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: isSmallScreen ? 48 : 56,
                      height: isSmallScreen ? 48 : 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFB8860B),
                            Color(0xFFC9A227),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFB8860B).withOpacity(0.3),
                            blurRadius: 12,
                            spreadRadius: 0,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.diamond,
                        color: Colors.black,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Grid Layout for Menu Items
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 16 : isTablet ? 32 : 24,
                    vertical: isSmallScreen ? 8 : 12,
                  ),
                  child: GridView.count(
                    crossAxisCount: isTablet ? 3 : 2,
                    crossAxisSpacing: isSmallScreen ? 12 : isTablet ? 20 : 16,
                    mainAxisSpacing: isSmallScreen ? 12 : isTablet ? 20 : 16,
                    childAspectRatio: isTablet ? 0.85 : 0.9,
                    children: [
                      _buildGridCard(
                        context,
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'View',
                       // subtitle: 'Scan QR',
                        color: const Color(0xFFB8860B),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ViewScreen(),
                            ),
                          );
                        },
                      ),
                      _buildGridCard(
                        context,
                        icon: Icons.shopping_cart_rounded,
                        title: 'Order',
                      //  subtitle: 'Place Order',
                        color: const Color(0xFFC9A227),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OrderFormScreen(),
                            ),
                          );
                        },
                      ),
                      _buildGridCard(
                        context,
                        icon: Icons.label_rounded,
                        title: 'Labels',
                      //  subtitle: 'Generate',
                        color: const Color(0xFFB8860B),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LabelScreen(),
                            ),
                          );
                        },
                      ),
                    _buildGridCard(
                      context,
                      icon: Icons.receipt_long_rounded,
                      title: 'Challan',
                      color: const Color(0xFFC9A227),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                           // builder: (context) => const ChallanMainScreen(),
                            builder: (context) => const CreateChallanOptionsScreen(),
                          ),
                        );
                      },
                    ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context, {
    required IconData icon,
    required String title,
   // required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isSmallScreen = screenSize.width < 360;
    
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : isTablet ? 24 : 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon Container
                Container(
                  width: isSmallScreen ? 56 : isTablet ? 72 : 64,
                  height: isSmallScreen ? 56 : isTablet ? 72 : 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withOpacity(0.2),
                        color.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.15),
                        blurRadius: 8,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: isSmallScreen ? 28 : isTablet ? 36 : 32,
                      color: color,
                    ),
                  ),
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : isTablet ? 20 : 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isSmallScreen ? 4 : 6),
                // Subtitle
                // Text(
                //   subtitle,
                //   style: TextStyle(
                //     fontSize: isSmallScreen ? 12 : isTablet ? 14 : 13,
                //     color: const Color(0xFF666666),
                //     fontWeight: FontWeight.w500,
                //   ),
                //   textAlign: TextAlign.center,
                // ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
