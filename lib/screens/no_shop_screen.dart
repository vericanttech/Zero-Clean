// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  No Shop Screen
//  Shown after login when the account has no shop assigned in Firestore.
//  Admin must create a shop document linked to this user's UID.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';

class NoShopScreen extends StatelessWidget {
  const NoShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.store_outlined,
                size: 64,
                color: ZCTheme.textMuted,
              ),
              const SizedBox(height: 24),
              Text(
                'Aucun magasin attribué',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: ZCTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun magasin n\'est associé à votre compte. Contactez votre administrateur pour qu\'il vous en attribue un.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ZCTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
