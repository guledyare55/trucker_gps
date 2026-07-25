import 'dart:math';

/// Calculates sunrise and sunset times using the NOAA solar equations.
/// No API key or internet required — pure math based on lat/lon and date.
class SunriseSunsetService {
  static final SunriseSunsetService _instance = SunriseSunsetService._internal();
  factory SunriseSunsetService() => _instance;
  SunriseSunsetService._internal();

  /// Returns true if it's currently night time at the given location.
  bool isNightTime(double latitude, double longitude) {
    final now = DateTime.now();
    final times = getSunriseSunset(latitude, longitude, now);
    if (times == null) return false;

    final sunrise = times.$1;
    final sunset = times.$2;

    // Night = before sunrise OR after sunset
    return now.isBefore(sunrise) || now.isAfter(sunset);
  }

  /// Returns (sunrise, sunset) as DateTime in local time for the given date.
  (DateTime, DateTime)? getSunriseSunset(
      double lat, double lon, DateTime date) {
    try {
      // Julian day number
      final jd = _julianDay(date);

      final sunrise = _calcSunriseSet(lat, lon, jd, true);
      final sunset = _calcSunriseSet(lat, lon, jd, false);

      if (sunrise == null || sunset == null) return null;

      final sunriseLocal = _minutesToLocalTime(sunrise, date);
      final sunsetLocal = _minutesToLocalTime(sunset, date);

      return (sunriseLocal, sunsetLocal);
    } catch (_) {
      return null;
    }
  }

  double _julianDay(DateTime date) {
    final y = date.year;
    final m = date.month;
    final d = date.day.toDouble();

    final a = ((14 - m) / 12).floor();
    final yAdj = y + 4800 - a;
    final mAdj = m + 12 * a - 3;

    return d +
        ((153 * mAdj + 2) / 5).floor() +
        365 * yAdj +
        (yAdj / 4).floor() -
        (yAdj / 100).floor() +
        (yAdj / 400).floor() -
        32045.0;
  }

  double? _calcSunriseSet(double lat, double lon, double jd, bool isRise) {
    const zenith = 90.833; // Official zenith for sunrise/sunset

    double longitude = lon;
    final lnHour = longitude / 15;

    final t = isRise ? jd + ((6 - lnHour) / 24) : jd + ((18 - lnHour) / 24);

    // Mean anomaly
    final m = (0.9856 * t) - 3.289;

    // Sun's true longitude
    var l = m +
        (1.916 * _sin(m)) +
        (0.020 * _sin(2 * m)) +
        282.634;
    l = _wrapTo360(l);

    // Right ascension
    var ra = _toDeg(atan(_toDeg(tan(_toRad(l))) / 15));
    final lQuadrant = (l / 90).floor() * 90;
    final raQuadrant = (ra / 90).floor() * 90;
    ra += lQuadrant - raQuadrant;
    ra /= 15;

    // Sun's declination
    final sinDec = 0.39782 * _sin(l);
    final cosDec = _cos(_toDeg(asin(sinDec)));

    // Local hour angle
    final cosH = (_cos(zenith) - (sinDec * _sin(lat))) /
        (cosDec * _cos(lat));

    if (cosH > 1 || cosH < -1) return null; // Midnight sun or polar night

    double h;
    if (isRise) {
      h = 360 - _toDeg(acos(cosH));
    } else {
      h = _toDeg(acos(cosH));
    }
    h /= 15;

    // Local mean time of rise/set
    final localMeanTime = h + ra - (0.06571 * t) - 6.622;

    // Adjust back to UTC
    var utc = localMeanTime - lnHour;
    utc = _wrapTo24(utc);

    // Return as minutes from midnight UTC
    return utc * 60;
  }

  DateTime _minutesToLocalTime(double minutesUtc, DateTime date) {
    final utcMidnight = DateTime.utc(date.year, date.month, date.day);
    final utcTime = utcMidnight.add(Duration(minutes: minutesUtc.round()));
    return utcTime.toLocal();
  }

  double _toRad(double deg) => deg * pi / 180.0;
  double _toDeg(double rad) => rad * 180.0 / pi;
  double _sin(double deg) => sin(_toRad(deg));
  double _cos(double deg) => cos(_toRad(deg));

  double _wrapTo360(double v) {
    while (v < 0) v += 360;
    while (v >= 360) v -= 360;
    return v;
  }

  double _wrapTo24(double v) {
    while (v < 0) v += 24;
    while (v >= 24) v -= 24;
    return v;
  }
}
