import 'package:flutter/material.dart';
import '../app_theme.dart';

class DialogAction {
  final String label;
  final bool primary;
  final bool destructive;
  final VoidCallback onTap;

  const DialogAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });
}

class AppDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? extra;
  final List<DialogAction> actions;

  const AppDialog({
    super.key,
    required this.title,
    required this.actions,
    this.content,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            if (content != null) ...[
              const SizedBox(height: 12),
              Text(
                content!,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textMuted, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            if (extra != null) ...[
              const SizedBox(height: 16),
              extra!,
            ],
            const SizedBox(height: 24),
            Row(
              children: actions.map((a) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: a == actions.first ? 0 : 6),
                    child: a.primary
                        ? ElevatedButton(
                            onPressed: a.onTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  a.destructive ? AppTheme.error : AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(a.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          )
                        : OutlinedButton(
                            onPressed: a.onTap,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(a.label,
                                style: const TextStyle(
                                    fontSize: 14, color: AppTheme.textMuted)),
                          ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
