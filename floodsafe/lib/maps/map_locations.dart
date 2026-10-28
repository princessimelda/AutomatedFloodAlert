import 'package:latlong2/latlong.dart';

import '../dashboard/dashboard_data.dart';

// Approximate neighbourhood reference points, not boundaries or safe locations.
// Source links and limitations are recorded in docs/maps.md.
const neighbourhoodCentres = <String, LatLng>{
  'kibera': LatLng(-1.30938, 36.78003),
  'westlands': LatLng(-1.266944, 36.811667),
  'embakasi': LatLng(-1.32361, 36.90000),
  'kasarani': LatLng(-1.22889, 36.90444),
};
const nairobiCentre = LatLng(-1.286389, 36.817223);
LatLng? mapPosition(Place? place) {
  if (place == null) return null;
  if (place.id.startsWith('gps:')) {
    final latitude = place.latitude;
    final longitude = place.longitude;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 85.05112878 ||
        longitude.abs() > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }
  return neighbourhoodCentres[place.id];
}
