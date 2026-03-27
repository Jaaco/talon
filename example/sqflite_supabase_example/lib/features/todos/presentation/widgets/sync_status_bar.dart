import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../todo_list_view_model.dart';

class SyncStatusBar extends StatelessWidget {
  final TodoListViewModel viewModel;
  final Future<void> Function() onReset;

  const SyncStatusBar({
    super.key,
    required this.viewModel,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isOnline = viewModel.isOnline.value;
      final isSyncing = viewModel.isSyncing.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBadge(isOnline: isOnline),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  onPressed: isSyncing ? null : viewModel.syncFromServer,
                  child: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sync, size: 16),
                            SizedBox(width: 6),
                            Text('Sync from server'),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ShadButton.outline(
                  onPressed: viewModel.toggleOnline,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isOnline ? Icons.wifi : Icons.wifi_off,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(isOnline ? 'Online' : 'Offline'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShadButton.destructive(
            onPressed: () async {
              await onReset();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restart_alt, size: 16),
                SizedBox(width: 6),
                Text('Fresh install / reset'),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOnline;

  const _StatusBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOnline
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOnline
              ? theme.colorScheme.primary
              : theme.colorScheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online — sync enabled' : 'Offline — local only',
            style: theme.textTheme.small,
          ),
        ],
      ),
    );
  }
}
