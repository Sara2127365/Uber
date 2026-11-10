
import 'package:flutter/material.dart';
import 'package:obar/feature/home/model/place_model.dart';
import 'package:obar/feature/home/services/search_service.dart';

class HomeSearchBar extends StatefulWidget {
  final ValueChanged<PlaceModel> onPlaceSelected;

  const HomeSearchBar({
    super.key,
    required this.onPlaceSelected,
  });

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final TextEditingController searchController =
      TextEditingController();

  final SearchService searchService = SearchService();

  List<PlaceModel> searchResults = [];
  bool showResults = false;

  void searchPlaces(String query) {
    setState(() {
      searchResults = searchService.searchPlaces(query);
      showResults = query.trim().isNotEmpty;
    });
  }

  void selectPlace(PlaceModel place) {
    searchController.text = place.name;

    setState(() {
      searchResults = [];
      showResults = false;
    });

    FocusScope.of(context).unfocus();
    widget.onPlaceSelected(place);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: TextField(
            controller: searchController,
            onChanged: searchPlaces,
            decoration: const InputDecoration(
              hintText: 'Search for a place',
              prefixIcon: Icon(Icons.search),
              border: InputBorder.none,
            ),
          ),
        ),
        if (showResults)
          Container(
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: searchResults.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text(
                      'No places found',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = searchResults[index];

                      return ListTile(
                        leading: const Icon(
                          Icons.location_on_outlined,
                        ),
                        title: Text(place.name),
                        subtitle: Text(place.address),
                        onTap: () => selectPlace(place),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
