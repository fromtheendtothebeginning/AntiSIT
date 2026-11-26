import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme_palette.dart';

/// anticlass 风格输入框：标签在玻璃面外（上方小字），输入面为独立玻璃块。
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.hintText,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.helperText,
    this.helperMaxLines,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final int? helperMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          enabled: enabled,
          autofocus: autofocus,
          maxLines: maxLines,
          textInputAction: textInputAction,
          validator: validator,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperMaxLines: helperMaxLines,
            errorMaxLines: 2,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

/// anticlass 风格下拉选择：标签在面外，同 [GlassField]。
class GlassDropdown<T> extends StatelessWidget {
  const GlassDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          // 展开占满整行：否则长选项会横向溢出。
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}

/// 与 [GlassField] 同款的「点开选择」字段：外观是输入框，点它弹出选择器。
class GlassPicker extends StatelessWidget {
  const GlassPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.prefixIcon,
    this.helperText,
    this.enabled = true,
  });

  final String label;

  /// 当前值（空串时显示 [hint]）。
  final String value;
  final String? hint;
  final VoidCallback onTap;
  final Widget? prefixIcon;
  final String? helperText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: SemColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SemColors.borderStrong),
                ),
                child: Row(
                  children: [
                    if (prefixIcon != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: SemColors.textSecondary, size: 20),
                        child: prefixIcon!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        empty ? (hint ?? '未选择') : value,
                        style: TextStyle(
                          fontSize: 14,
                          color: empty ? SemColors.textMuted : SemColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more_rounded,
                        size: 20, color: SemColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(helperText!,
              style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.4)),
        ],
      ],
    );
  }
}
