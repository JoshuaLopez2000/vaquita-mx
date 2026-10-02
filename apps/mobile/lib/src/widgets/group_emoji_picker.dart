import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

Future<String?> showGroupEmojiPicker(
  BuildContext context,
) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
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
          categoryViewConfig: const CategoryViewConfig(
            initCategory: Category.SMILEYS,
          ),
          emojiViewConfig: const EmojiViewConfig(noRecents: SizedBox.shrink()),
        ),
      ),
    ),
  );
}
