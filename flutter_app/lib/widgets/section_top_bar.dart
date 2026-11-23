import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SectionTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionTopBar({
    super.key,
    required this.title,
    this.icon,
    this.onBack,
    this.showBack = true,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.onAction,
    this.actionWidget,
    this.extraActions,
    this.bottom,
  });

  final String title;
  final IconData? icon;
  final VoidCallback? onBack;
  final bool showBack;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final Widget? actionWidget;
  final List<Widget>? extraActions;
  final PreferredSizeWidget? bottom;

  static const double kTopInset = 16.0;

  @override
  Size get preferredSize =>
      Size.fromHeight(53.0 + kTopInset + (bottom?.preferredSize.height ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final double endMargin = (actionWidget != null || (actionLabel != null && onAction != null))
        ? 120.0
        : ((extraActions != null && extraActions!.isNotEmpty) ? 50.0 * extraActions!.length + 10.0 : 54.0);
    final double startMargin = showBack ? 54.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: kTopInset),
          SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Centered Title (مختصر وفي المنتصف تماماً دون أي تداخل)
                Positioned.fill(
                  left: isRtl ? endMargin : startMargin,
                  right: isRtl ? startMargin : endMargin,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 19, color: primaryColor),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontFamily: 'Cairo',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Start side: Back button (باصص لليمين)
                if (showBack)
                  PositionedDirectional(
                    start: 10,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (onBack != null) {
                          onBack!();
                        } else if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                          textDirection: TextDirection.ltr, // مضمون 100% يشير لليمين
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),

                // 3. End side: Action button / Add button
                PositionedDirectional(
                  end: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (actionWidget != null)
                        actionWidget!
                      else if (actionLabel != null && onAction != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            minimumSize: const Size(0, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: Icon(actionIcon, size: 15),
                          label: Text(
                            actionLabel!,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'Cairo'),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onAction!();
                          },
                        ),
                      if (extraActions != null) ...extraActions!,
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}
