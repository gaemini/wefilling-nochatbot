// lib/widgets/translating_text.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class TranslatingText extends StatelessWidget {
  final String originalText;
  final Future<String> Function(SettingsProvider) translateFuture;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const TranslatingText({
    Key? key,
    required this.originalText,
    required this.translateFuture,
    this.style,
    this.maxLines,
    this.overflow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    if (!settings.autoTranslate) {
      return Text(
        originalText,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return FutureBuilder<String>(
      future: translateFuture(settings),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              Text(
                originalText,
                style: style,
                maxLines: maxLines,
                overflow: overflow,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ],
          );
        }

        return Text(
          snapshot.data ?? originalText,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}