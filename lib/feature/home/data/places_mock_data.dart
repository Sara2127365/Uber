import 'package:obar/feature/home/model/place_model.dart';

class PlacesMockData {
  static const List<PlaceModel> places = [
    PlaceModel(
      name: 'Cairo University',
      address: 'Cairo University, Giza, Egypt',
      latitude: 30.0276,
      longitude: 31.2089,
    ),
    PlaceModel(
      name: 'Giza Zoo',
      address: 'Giza Zoo, Giza, Egypt',
      latitude: 30.0259,
      longitude: 31.2167,
    ),
    PlaceModel(
      name: 'Cairo Tower',
      address: 'Cairo Tower, Zamalek, Cairo, Egypt',
      latitude: 30.0459,
      longitude: 31.2243,
    ),
    PlaceModel(
      name: 'The Egyptian Museum',
      address: 'Tahrir Square, Downtown Cairo, Egypt',
      latitude: 30.0478,
      longitude: 31.2336,
    ),
    PlaceModel(
      name: 'Mall of Egypt',
      address: 'Wahat Road, 6th of October City, Giza, Egypt',
      latitude: 29.9728,
      longitude: 31.0168,
    ),
  ];
}