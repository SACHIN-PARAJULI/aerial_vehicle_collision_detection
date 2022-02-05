import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' show RobustLineIntersector, Coordinate;
import 'package:flutter_map/flutter_map.dart';

List<List<Coordinate>> coordinatesToLines(
    List<LatLng> latLngList, double zoom) {
  List<List<Coordinate>> lines = [];
  LatLng previousLatLng = latLngList[0];
  for (var latLng in latLngList) {
    CustomPoint point1 = Epsg3857().latLngToPoint(previousLatLng, zoom);
    CustomPoint point2 = Epsg3857().latLngToPoint(latLng, zoom);

    lines.add([
      Coordinate(point1.x.toDouble(), point1.y.toDouble()),
      Coordinate(point2.x.toDouble(), point2.y.toDouble())
    ]);
    previousLatLng = latLng;
  }
  return lines;
}

List<LatLng> getCollisionLatLngList(
    List<List<Coordinate>> lines1, List<List<Coordinate>> lines2, double zoom) {
  List<LatLng> collisionLatLngList = [];
  for (List<Coordinate> line1 in lines1) {
    for (List<Coordinate> line2 in lines2) {
      if (line1 != line2) {
        RobustLineIntersector intersect = RobustLineIntersector();
        intersect.computeIntersection(line1[0], line1[1], line2[0], line2[1]);
        if (intersect.hasIntersection() && intersect.isProper()) {
          Coordinate intersectPoint = intersect.getIntersection(0);
          LatLng? currentLatLng = const Epsg3857().pointToLatLng(
              CustomPoint(intersectPoint.x, intersectPoint.y), zoom);

          bool isInList = false;
          for (LatLng latlng in collisionLatLngList) {
            if (latlng == currentLatLng) {
              isInList = true;
            }
          }

          if (!isInList) {
            collisionLatLngList.add(currentLatLng!);
          }
        }
      }
    }
  }
  print(collisionLatLngList);
  return collisionLatLngList;
}

routeSendDialog(BuildContext context, List<LatLng> latLngList,
    CollectionReference flightPlans) {
  final _formKey = GlobalKey<FormState>();
  DateTime selectedDate = DateTime.now();
  final TextEditingController _speedController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  showDialog(
      context: context,
      builder: (BuildContext builder) {
        return AlertDialog(
          content: Container(
            child: Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    controller: _speedController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "Speed",
                    ),
                  ),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(hintText: "Username"),
                  ),
                  ElevatedButton(
                      onPressed: () async {
                        final DateTime? flightDay = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            initialDatePickerMode: DatePickerMode.day,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2101));
                        if (flightDay != null) {
                          print(flightDay);
                          final TimeOfDay? timeStart = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (timeStart != null) {
                            print(timeStart);
                            final TimeOfDay? timeEnd = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );

                            if (timeEnd != null) {
                              if ((timeEnd.hour - timeStart.hour) >= 1) {
                                if (_usernameController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text("Please enter your username."),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text("Sending Flight Plan..."),
                                  ));

                                  flightPlans.add({
                                    "routes": latLngList.map((e) {
                                      return GeoPoint(e.latitude, e.longitude);
                                    }).toList(),
                                    "username": _usernameController.text,
                                    "datetime": flightDay,
                                    "startTime": {
                                      "hour": timeStart.hour,
                                      "minute": timeStart.minute
                                    },
                                    "endTime": {
                                      "hour": timeEnd.hour,
                                      "minute": timeEnd.minute
                                    }
                                  }).then((value) async {
                                    SharedPreferences prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setInt("routesSent", 1);
                                    prefs.setInt(
                                        "startTimeHour", timeStart.hour);
                                    prefs.setInt(
                                        "startTimeMinute", timeStart.minute);

                                    prefs.setInt("endTimeHour", timeEnd.hour);
                                    prefs.setInt(
                                        "endTimeMinute", timeEnd.minute);
                                    prefs.setInt('flighTimestamp',
                                        flightDay.millisecondsSinceEpoch);

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            "Flight Plan successfully sent!"),
                                      ),
                                    );
                                    Navigator.of(context).pop();
                                  }).catchError((error) {
                                    print(error);
                                  });
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        "StartTime must occur before EndTime."),
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                      child: const Text("Select Day of Flight"))
                ])),
          ),
        );
      });
}

bool timeCoincides(List<TimeOfDay> timeRange1, List<TimeOfDay> timeRange2) {
  List<double> timeRange1Db = timeInDouble(timeRange1);
  List<double> timeRange2Db = timeInDouble(timeRange2);

  List<double> firstTimeRange;
  List<double> secondTimeRange;
  if (timeRange1Db[0] <= timeRange2Db[0]) {
    firstTimeRange = timeRange1Db;
    secondTimeRange = timeRange2Db;
  } else {
    firstTimeRange = timeRange2Db;
    secondTimeRange = timeRange1Db;
  }
  return (secondTimeRange[0] <= firstTimeRange[1]);
}

List<double> timeInDouble(List<TimeOfDay> timeRange) {
  return timeRange
      .map((time) => (time.hour.toDouble() + time.minute.toDouble() / 60))
      .toList();
}
