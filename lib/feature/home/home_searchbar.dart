import 'package:flutter/material.dart';
import 'package:obar/core/style/color_manager.dart';

class HomeSearchBar extends StatelessWidget {
  final ValueChanged<String>? onSearch;

  const HomeSearchBar({
    super.key,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 43,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ColorManager.borderColor,
              ),
            ),
            child: TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                hintText: 'Where to ?',
                hintStyle: TextStyle(
                  color: ColorManager.greyColor,
                  fontSize: 12,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: ColorManager.greyColor,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 43,
          width: 43,
          decoration: BoxDecoration(
            color: ColorManager.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.filter_list,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}