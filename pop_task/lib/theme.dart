import 'package:flutter/material.dart';

const kMint = Color(0xFFDAECE0);
const kCream = Color(0xFFFFFDF5);
const kSun = Color(0xFFFFDE00);
const kField = Color(0xFFF9FAFB);
const kChipOff = Color(0xFFF3F4F6);
const kDoneGrey = Color(0xFFE5E7EB);
const kOverdue = Color(0xFFFFB4A8);

final kDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(16),
  side: const BorderSide(color: Colors.black, width: 2),
);

final kPrimaryButton = ElevatedButton.styleFrom(
  backgroundColor: kMint,
  foregroundColor: Colors.black,
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
);

const kDialogTitle = TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black);
const kFieldLabel = TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.black54);

InputDecoration fieldDecoration({String hint = ''}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: kField,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Colors.black26),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Colors.black26),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: kMint, width: 2),
  ),
);

/// The app's standard dialog: white, black 2px border.
class BrutalDialog extends StatelessWidget {
  const BrutalDialog({super.key, required this.title, required this.content, required this.actions});

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: kDialogShape,
    title: DefaultTextStyle.merge(style: kDialogTitle, child: title),
    content: content,
    actions: actions,
  );
}

class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.label = 'CANCEL'});
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.pop(context),
    child: Text(
      label,
      style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
    ),
  );
}

/// Small bordered tag, e.g. "DAILY" or a due time.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = kSun, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    margin: const EdgeInsets.only(left: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.black, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 10, color: Colors.black), const SizedBox(width: 3)],
        Text(
          text,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black),
        ),
      ],
    ),
  );
}
