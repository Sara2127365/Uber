
import 'package:flutter/material.dart';
import 'package:obar/core/style/color_manager.dart';


class AppCustomBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final Widget? action;
  final VoidCallback? onBackPressed;

  const AppCustomBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.action,
    this.onBackPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(65);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: showBackButton ? 0 : 20,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: ColorManager.textColor,
              ),
              onPressed: onBackPressed ??
                  () => Navigator.maybePop(context),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          color: ColorManager.textColor,
          fontWeight: FontWeight.w800,
          fontSize: 24,
        ),
      ),
      actions: action == null ? null : [action!],
    );
  }
}
