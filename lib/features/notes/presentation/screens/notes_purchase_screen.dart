import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notes/presentation/controllers/notes_controller.dart';

class NotesPurchaseScreen extends ConsumerStatefulWidget {
  const NotesPurchaseScreen({super.key});

  @override
  ConsumerState<NotesPurchaseScreen> createState() =>
      _NotesPurchaseScreenState();
}

class _NotesPurchaseScreenState extends ConsumerState<NotesPurchaseScreen> {
  late Razorpay _razorpay;
  bool _loading = false;
  Map<String, dynamic>? _pendingOrderData;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    if (!kIsWeb) {
      _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      _razorpay.clear();
    }
    super.dispose();
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (_pendingOrderData == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _pendingOrderData = null; // consume — never re-verify a stale order

    final success = await ref.read(notesControllerProvider.notifier).verifyPurchase(
          orderId: response.orderId ?? '',
          paymentId: response.paymentId ?? '',
          signature: response.signature ?? '',
        );

    if (!mounted) return;
    // Always clear the spinner — otherwise a failed verify left the unlock
    // button a permanent disabled spinner with no way to retry.
    setState(() => _loading = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access granted! Enjoy your notes.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment verification failed. Contact support.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Payment failed. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External wallet selected: ${response.walletName}'),
        ),
      );
    }
  }

  Future<void> _onUnlockTap() async {
    setState(() => _loading = true);
    try {
      final orderData =
          await ref.read(notesControllerProvider.notifier).purchaseNotes();

      // Dev mode or user already has access — granted directly without payment
      final status = orderData['status'] as String?;
      if (status == 'granted' || status == 'already_granted') {
        await ref.read(notesControllerProvider.notifier).checkAccess();
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access granted! Enjoy your notes.'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        }
        return;
      }

      // Production — open Razorpay (native only; web uses a different checkout flow)
      if (kIsWeb) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please use the mobile app to complete payment.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      _pendingOrderData = orderData;
      final options = {
        'key': orderData['key_id'],
        'amount': orderData['amount'],
        'currency': orderData['currency'],
        'order_id': orderData['order_id'],
        'name': 'APX PRO',
        'description': 'Premium Notes Pack',
        'prefill': {'email': '', 'contact': ''},
      };
      _razorpay.open(options);
      // Loading will be cleared in success/error callbacks
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate purchase: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: 'Unlock Premium Notes'),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),

                // Header icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.primary,
                    size: 48,
                  ),
                ),

                const SizedBox(height: 24),

                // Title
                const Text(
                  'Premium Notes Pack',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Price badge
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  borderRadius: BorderRadius.circular(32),
                  tint: AppColors.primary.withValues(alpha: 0.1),
                  child: const Text(
                    '₹100 — One Time',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Benefits list
                _buildBenefitCard(
                  icon: Icons.all_inclusive,
                  title: 'All Current & Future Notes',
                  subtitle:
                      'Get instant access to every note we publish — now and forever.',
                ),
                const SizedBox(height: 12),
                _buildBenefitCard(
                  icon: Icons.workspace_premium,
                  title: 'Lifetime Access',
                  subtitle:
                      'Pay once, access forever. No recurring subscription.',
                ),
                const SizedBox(height: 12),
                _buildBenefitCard(
                  icon: Icons.category,
                  title: 'All Categories',
                  subtitle:
                      'Anatomy, Physiology, Pharmacology, and more — all covered.',
                ),
                const SizedBox(height: 12),
                _buildBenefitCard(
                  icon: Icons.devices,
                  title: 'Multi-format Support',
                  subtitle:
                      'PDF, images, slides, and documents — view everything in-app.',
                ),

                const SizedBox(height: 40),

                // Unlock button
                GlassButton(
                  label: 'Unlock Now — ₹100',
                  onTap: _loading ? null : _onUnlockTap,
                  style: GlassButtonStyle.primary,
                  loading: _loading,
                  width: double.infinity,
                ),

                const SizedBox(height: 16),

                const Text(
                  'Secure payment powered by Razorpay',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
