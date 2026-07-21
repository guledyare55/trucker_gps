import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/providers/api_providers.dart';
import 'package:trucker_gps/services/api_service.dart';

class HosLogbookScreen extends ConsumerStatefulWidget {
  final String userId;

  const HosLogbookScreen({Key? key, required this.userId}) : super(key: key);

  @override
  ConsumerState<HosLogbookScreen> createState() => _HosLogbookScreenState();
}

class _HosLogbookScreenState extends ConsumerState<HosLogbookScreen> {
  Future<void> _updateStatus(String status) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateDutyStatus(widget.userId, status);
      // Refresh the provider
      ref.invalidate(hosSummaryProvider(widget.userId));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosAsync = ref.watch(hosSummaryProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('HOS Logbook (ELD)'),
      ),
      body: hosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Failed to load HOS: $err'),
              ElevatedButton(
                onPressed: () => ref.invalidate(hosSummaryProvider(widget.userId)),
                child: const Text('Retry'),
              )
            ],
          ),
        ),
        data: (summary) {
          final violations = summary['violations'] as List? ?? [];
          final currentStatus = summary['current_status'] ?? 'off_duty';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Current Status', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          currentStatus.toString().toUpperCase().replaceAll('_', ' '),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Status Toggle Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildStatusButton('off_duty', 'OFF DUTY', currentStatus),
                    _buildStatusButton('sleeper_berth', 'SLEEPER', currentStatus),
                    _buildStatusButton('driving', 'DRIVING', currentStatus),
                    _buildStatusButton('on_duty', 'ON DUTY', currentStatus),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Clocks
                const Text('Remaining Time Clocks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildClockCard(
                  'Driving Time (11 hr limit)',
                  '${summary['driving_hours_remaining']} hrs',
                  summary['driving_hours_remaining'] < 2.0,
                ),
                _buildClockCard(
                  'Shift/Duty Window (14 hr limit)',
                  '${summary['duty_window_hours_remaining']} hrs',
                  summary['duty_window_hours_remaining'] < 2.0,
                ),
                _buildClockCard(
                  'Weekly Cycle (70 hr limit)',
                  '${summary['eight_day_remaining']} hrs',
                  summary['eight_day_remaining'] < 5.0,
                ),
                
                const SizedBox(height: 24),
                
                // Violations
                if (violations.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 8),
                            Text(
                              'HOS Violations',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...violations.map((v) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• ${v['message']}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        )).toList(),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusButton(String statusId, String label, String currentStatus) {
    final isSelected = statusId == currentStatus;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceVariant,
        foregroundColor: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
        minimumSize: const Size(150, 50),
      ),
      onPressed: isSelected ? null : () => _updateStatus(statusId),
      child: Text(label),
    );
  }

  Widget _buildClockCard(String title, String timeRemaining, bool isWarning) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isWarning ? Colors.orange.shade100 : null,
      child: ListTile(
        title: Text(title, style: TextStyle(color: isWarning ? Colors.deepOrange.shade900 : null)),
        trailing: Text(
          timeRemaining,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isWarning ? Colors.deepOrange.shade900 : Colors.green,
          ),
        ),
      ),
    );
  }
}
