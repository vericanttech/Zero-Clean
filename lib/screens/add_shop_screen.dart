// Thin wrapper — navigates to setup tab and opens the add-shop sheet
// Used from the dashboard AppBar shortcut
import 'package:flutter/material.dart';
import 'setup_screen.dart';

class AddShopScreen extends StatelessWidget {
  const AddShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Just show the setup screen; users can add shops there
    return const SetupScreen();
  }
}
