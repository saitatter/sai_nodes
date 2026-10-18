import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'catalog.dart';

/// Compact controls that fit the editor's standard field rows.
class InlineField extends StatelessWidget {
  const InlineField({
    super.key,
    required this.field,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.onEditJson,
  });
  final DemoField field;
  final Object? value;
  final Color color;
  final ValueChanged<Object?> onChanged;
  final VoidCallback onEditJson;

  @override
  Widget build(BuildContext context) {
    final label = Expanded(
      child: Text(
        field.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10),
      ),
    );
    switch (field.kind) {
      case GraphFieldKind.boolean:
        return Row(
          children: [
            label,
            Checkbox(
              value: value == true,
              activeColor: color,
              onChanged: (value) => onChanged(value == true),
            ),
          ],
        );
      case GraphFieldKind.number:
        final number = value is num ? (value as num).toDouble() : field.min;
        final display = number.toStringAsFixed(field.max <= 1 ? 2 : 1);
        return Tooltip(
          message: '${field.label}: $display',
          child: Row(
            children: [
              label,
              Expanded(
                flex: 2,
                // A compact slider without a global value-indicator overlay.
                child: Semantics(
                  label: field.label,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      final key = event.logicalKey;
                      final direction =
                          key == LogicalKeyboardKey.arrowRight ||
                              key == LogicalKeyboardKey.arrowUp
                          ? 1
                          : key == LogicalKeyboardKey.arrowLeft ||
                                key == LogicalKeyboardKey.arrowDown
                          ? -1
                          : 0;
                      if (direction == 0) return KeyEventResult.ignored;
                      onChanged(
                        (number + direction * (field.max - field.min) / 20)
                            .clamp(field.min, field.max),
                      );
                      return KeyEventResult.handled;
                    },
                    child: Builder(
                      builder: (context) => Listener(
                        onPointerDown: (_) => Focus.of(context).requestFocus(),
                        child: CupertinoSlider(
                          min: field.min,
                          max: field.max,
                          value: number.clamp(field.min, field.max),
                          activeColor: color,
                          thumbColor: color,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 35,
                child: Text(
                  display,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ),
            ],
          ),
        );
      case GraphFieldKind.choice:
        return Row(
          children: [
            label,
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                value: field.choices.contains(value) ? value as String : null,
                hint: Text(field.label),
                style: TextStyle(color: color, fontSize: 11),
                items: [
                  for (final choice in field.choices)
                    DropdownMenuItem(value: choice, child: Text(choice)),
                ],
                onChanged: onChanged,
              ),
            ),
          ],
        );
      case GraphFieldKind.json:
        return TextButton.icon(
          onPressed: onEditJson,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: color,
          ),
          icon: const Icon(Icons.edit_outlined, size: 13),
          label: Text(
            'Edit ${field.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        );
      default:
        return InlineText(
          value: '$value',
          label: field.label,
          onChanged: onChanged,
        );
    }
  }
}

/// Retains the caret during live edits, while reflecting undo and imported data.
class InlineText extends StatefulWidget {
  const InlineText({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.maxLines = 1,
  });
  final String value, label;
  final ValueChanged<String> onChanged;
  final int maxLines;
  @override
  State<InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<InlineText> {
  late final text = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(InlineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (text.text != widget.value) {
      text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: text,
    minLines: 1,
    maxLines: widget.maxLines,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    decoration: InputDecoration(
      isDense: true,
      hintText: widget.label,
      semanticCounterText: widget.label,
      contentPadding: const EdgeInsets.symmetric(vertical: 3),
      border: InputBorder.none,
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xff50576a)),
      ),
      focusedBorder: const UnderlineInputBorder(),
    ),
    onChanged: widget.onChanged,
  );
}
