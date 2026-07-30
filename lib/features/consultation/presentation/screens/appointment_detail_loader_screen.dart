import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/consultation/data/appointment_model.dart';
import 'package:apx_pro/features/consultation/presentation/controllers/appointment_controller.dart';
import 'package:apx_pro/features/consultation/presentation/screens/appointment_detail_screen.dart';

/// Resolves an appointment by id and shows its details. Used by notification
/// deep-links, which only carry the appointment id. Works for both patients and
/// admins because `/appointments/my` returns the caller's visible appointments.
///
/// If a full model is already available (e.g. navigated from a list), it is
/// passed as [preloaded] and rendered immediately without a fetch.
class AppointmentDetailLoaderScreen extends ConsumerStatefulWidget {
  const AppointmentDetailLoaderScreen({
    super.key,
    required this.appointmentId,
    this.preloaded,
  });

  final String appointmentId;
  final AppointmentModel? preloaded;

  @override
  ConsumerState<AppointmentDetailLoaderScreen> createState() =>
      _AppointmentDetailLoaderScreenState();
}

class _AppointmentDetailLoaderScreenState
    extends ConsumerState<AppointmentDetailLoaderScreen> {
  AppointmentModel? _appointment;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _appointment = widget.preloaded;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final list =
          await ref.read(appointmentRepositoryProvider).fetchMyAppointments();
      AppointmentModel? found;
      for (final a in list) {
        if (a.id == widget.appointmentId) {
          found = a;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _appointment = found;
          _notFound = found == null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: 'Appointment',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const GlassOrbBackground(
          child: Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }
    // AppointmentDetailScreen renders a graceful "no longer available" state
    // when the appointment is null, covering the not-found case.
    return AppointmentDetailScreen(
      appointment: _notFound ? null : _appointment,
    );
  }
}
