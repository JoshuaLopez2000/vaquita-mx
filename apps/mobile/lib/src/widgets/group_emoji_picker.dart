import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

Future<String?> showGroupEmojiPicker(
  BuildContext context,
) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: 360,
      child: EmojiPicker(
        onEmojiSelected: (_, emoji) =>
            Navigator.of(sheetContext).pop(emoji.emoji),
        onBackspacePressed: null,
        config: Config(
          height: 360,
          locale: Localizations.localeOf(context),
          categoryViewConfig: CategoryViewConfig(
            initCategory: Category.SMILEYS,
            backgroundColor: colors.surfaceContainerLowest,
            indicatorColor: colors.primary,
            iconColorSelected: colors.primary,
            iconColor: colors.onSurfaceVariant,
          ),
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: colors.surfaceContainerLowest,
            noRecents: const SizedBox.shrink(),
          ),
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
        ),
      ),
    ),
  );
}
