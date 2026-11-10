import 'package:obar/feature/home/data/places_mock_data.dart';
import 'package:obar/feature/home/model/place_model.dart';

class SearchService {
  List<PlaceModel> searchPlaces(String query) {
    if (query.isEmpty) {
      return [];
    }

    return PlacesMockData.places.where((place) {
      return place.name.toLowerCase().contains(
        query.toLowerCase(),
      );
    }).toList();
  }
}