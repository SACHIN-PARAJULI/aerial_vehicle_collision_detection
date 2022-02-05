import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' show RobustLineIntersector, Coordinate;

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var logicalScreenSize = window.physicalSize / window.devicePixelRatio;

  IconData floatingIcon = Icons.add_location_alt;
  MaterialColor floatingColor = Colors.blue;
  bool selectionEnabled = false;

  int droneLocation = 0;
  double droneSpeed = 200; //in m/s

  List<LatLng> latLngList = [];
  List<LatLng> miniLatLngList = [];
  List<LatLng> collisionLatLngList = [];
  List<List<LatLng>> otherPlanLatLngList = [];

  LatLng droneLocationLatLng = LatLng(26.790952, 87.290985);

  final TextEditingController _speedController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  late MapController mapController;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    innitializeStorage();
    latLngStream();
  }

  Future<void> innitializeStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt("routesSent", 0);
  }

  List<Marker> generateMarkers(List<LatLng> latlanglist) {
    List<Marker> markers = latlanglist
        .map((point) => Marker(
              point: point,
              width: 40,
              height: 40,
              builder: (context) => const Icon(
                Icons.location_pin,
                size: 40,
                color: Colors.orange,
              ),
            ))
        .toList();
    return markers;
  }

  List<Marker> generateCollisionMarkers() {
    List<Marker> markers = collisionLatLngList
        .map((point) => Marker(
              point: point,
              width: 20,
              height: 20,
              builder: (context) => const Icon(
                Icons.circle,
                size: 20,
                color: Colors.red,
              ),
            ))
        .toList();
    return markers;
  }

  List<Marker> generateOtherPlanMarkers() {
    List<Marker> allMarkers = [];
    for (List<LatLng> otherPlanLatLng in otherPlanLatLngList) {
      List<Marker> markers = otherPlanLatLng
          .map((point) => Marker(
                point: point,
                width: 40,
                height: 40,
                builder: (context) => const Icon(
                  Icons.location_pin,
                  size: 40,
                  color: Colors.red,
                ),
              ))
          .toList();
      allMarkers.addAll(markers);
    }
    return allMarkers;
  }

  List<Marker> generateMiniMarkers() {
    if (latLngList.length >= 2) {
      LatLng lastCor = latLngList[latLngList.length - 1];
      final Path path = Path.from(latLngList);
      if (_speedController.text.isNotEmpty) {
        droneSpeed = double.parse(_speedController.text);
      }
      final Path steps = path.equalize(droneSpeed, smoothPath: false);
      miniLatLngList = [
        ...steps.coordinates,
        lastCor,
      ];
    }

    List<Marker> markers = miniLatLngList
        .map((point) => Marker(
              point: point,
              width: 10,
              height: 10,
              builder: (context) => const Icon(
                Icons.circle,
                size: 10,
                color: Colors.blueGrey,
              ),
            ))
        .toList();
    return markers;
  }

  List<Marker> dronePosition() {
    if (latLngList.length > 1) {
      return [
        Marker(
          point: miniLatLngList[droneLocation],
          width: 100,
          height: 100,
          builder: (context) => Image.asset(
            "assets/drone1.png",
          ),
        )
      ];
    } else {
      CollectionReference drones =
          FirebaseFirestore.instance.collection('currentDrones');

      drones.add({
        'lastUpdated': DateTime.now(),
        'location': GeoPoint(
            droneLocationLatLng.latitude, droneLocationLatLng.longitude)
      });

      return [
        Marker(
          point: droneLocationLatLng,
          width: 100,
          height: 100,
          builder: (context) => Image.asset(
            "assets/drone1.png",
          ),
        )
      ];
    }
  }

  List<CircleMarker> getCircleMarkers() {
    if (miniLatLngList.isNotEmpty) {
      return <CircleMarker>[
        CircleMarker(
            point: miniLatLngList[droneLocation],
            color: Colors.blue.withOpacity(0.1),
            borderColor: Colors.orange,
            borderStrokeWidth: 1,
            useRadiusInMeter: true,
            radius: 2000 // 2000 meters | 2 km
            ),
      ];
    } else {
      return [];
    }
  }

  CollectionReference drones =
      FirebaseFirestore.instance.collection('currentDrones');

  Future<void> latLngStream() async {
    Timer.periodic(Duration(seconds: 10), (timer) {
      drones.get().then((response) {
        for (var doc in response.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          DateTime lastUpdated = data['lastUpdated'].toDate();
          Duration timeDiff = DateTime.now().difference(lastUpdated);
          print(timeDiff);
          print(timeDiff.inMinutes);
          if (selectionEnabled && timeDiff.inMinutes <= 10) {
            final Distance distance = Distance();

            GeoPoint location = data['location'];

            double distanceMeters = distance(
                miniLatLngList[droneLocation], getCurrentLocation(location));

            if (distanceMeters <= 2000) {
              print(location);
            }
          }
        }
      });
    });
  }

  LatLng getCurrentLocation(GeoPoint locGeo) {
    return LatLng(locGeo.latitude, locGeo.longitude);
  }

  @override
  Widget build(BuildContext context) => RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (event) {
          if (event.isShiftPressed) {
            Timer.periodic(const Duration(seconds: 1), (timer) {
              if ((miniLatLngList.length - 1 > droneLocation) &&
                  selectionEnabled) {
                print("reached inside");
                setState(() {
                  droneLocation += 1;
                });
              } else {
                timer.cancel();
              }
            });
          }
          if (event.isControlPressed) {
            print("contro pressed");
            if (latLngList.length >= 2) {
              print("running algo");
              LatLng previousCor = latLngList[0];
              List<List<LatLng>> linesCors = [];
              for (var i = 1; i < latLngList.length; i++) {
                linesCors.add([previousCor, latLngList[i]]);
                previousCor = latLngList[i];
              }
              List<List<Coordinate>> lines = [];
              double zoom = mapController.zoom;
              for (var lineCors in linesCors) {
                CustomPoint point1 =
                    Epsg3857().latLngToPoint(lineCors[0], zoom);
                CustomPoint point2 =
                    Epsg3857().latLngToPoint(lineCors[1], zoom);

                lines.add([
                  Coordinate(point1.x.toDouble(), point1.y.toDouble()),
                  Coordinate(point2.x.toDouble(), point2.y.toDouble())
                ]);
              }

              for (List<Coordinate> line1 in lines) {
                for (List<Coordinate> line2 in lines) {
                  if (line1 != line2) {
                    RobustLineIntersector intersect = RobustLineIntersector();
                    intersect.computeIntersection(
                        line1[0], line1[1], line2[0], line2[1]);
                    if (intersect.hasIntersection() && intersect.isProper()) {
                      Coordinate intersectPoint = intersect.getIntersection(0);
                      LatLng? currentLatLng = const Epsg3857().pointToLatLng(
                          CustomPoint(intersectPoint.x, intersectPoint.y),
                          zoom);

                      bool isInList = false;
                      for (LatLng latlng in collisionLatLngList) {
                        if (latlng == currentLatLng) {
                          isInList = true;
                        }
                      }
                      if (!isInList) {
                        setState(() {
                          collisionLatLngList.add(currentLatLng!);
                        });
                      }
                    }
                  }
                }
              }

              print(collisionLatLngList);
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            title: const Text("Map Text"),
          ),
          body: Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                    center: LatLng(26.790952, 87.290985),
                    zoom: 13.0,
                    onTap: (position, currentLatLng) {
                      if (selectionEnabled) {
                        setState(() {
                          latLngList.add(currentLatLng);
                        });
                      } else {
                        setState(() {
                          droneLocationLatLng = currentLatLng;
                        });
                      }
                    }),
                layers: [
                  TileLayerOptions(
                    urlTemplate:
                        "https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v11/tiles/"
                        "{z}/{x}/{y}?access_token=sk.eyJ1Ijoic3VyYWpiZXN0b24iLCJhIjoiY2t6MnJpbGEyMDBuMjJ2cDRudmZmcmRjdCJ9.e9gD9AYCQH4b8i5f9nEvZQ",
                  ),
                  MarkerLayerOptions(markers: [
                    ...generateMarkers(latLngList),
                    ...generateMiniMarkers(),
                    // ...generateOtherPlanMarkers(),
                    ...generateCollisionMarkers(),
                    ...dronePosition(),
                  ]),
                  PolylineLayerOptions(
                    polylines: [
                      Polyline(
                        points: latLngList,
                        strokeWidth: 1.0,
                        color: Colors.yellow,
                      ),
                      // Polyline(
                      //   points: otherPlanLatLngList,
                      //   strokeWidth: 1.0,
                      //   color: Colors.red.shade200,
                      // )
                    ],
                  ),
                  CircleLayerOptions(circles: getCircleMarkers())
                ],
              ),
              Container(
                height: 200,
                alignment: const Alignment(0, -1),
                child: Column(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        textAlign: TextAlign.center,
                        controller: _speedController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: "200",
                          hintStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 350,
                      // alignment: const Alignment(1, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(right: 10),
                            child: ElevatedButton(
                              onPressed: () {
                                if (latLngList.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Please add some locations to mark your route."),
                                    ),
                                  );
                                } else {
                                  CollectionReference flightPlans =
                                      FirebaseFirestore.instance
                                          .collection('flightPlansNew');
                                  routeSendDialog(
                                      context, latLngList, flightPlans);
                                }
                              },
                              child: const Text("DEPLOY ROUTES"),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              SharedPreferences prefs =
                                  await SharedPreferences.getInstance();
                              int? routesSent = prefs.getInt("routesSent");
                              if (routesSent == 1) {
                                CollectionReference flightPlans =
                                    FirebaseFirestore.instance
                                        .collection('flightPlansNew');

                                flightPlans.get().then((response) async {
                                  List<List<LatLng>> outRoutes = [];

                                  for (var doc in response.docs) {
                                    Map<String, dynamic> data =
                                        doc.data() as Map<String, dynamic>;

                                    Timestamp datetimeTimestamp =
                                        data['datetime'];
                                    DateTime date = datetimeTimestamp.toDate();
                                    SharedPreferences prefs =
                                        await SharedPreferences.getInstance();
                                    TimeOfDay startTimeCurrent = TimeOfDay(
                                        hour: prefs.getInt("startTimeHour")!,
                                        minute:
                                            prefs.getInt("startTimeMinute")!);

                                    TimeOfDay endTimeCurrent = TimeOfDay(
                                        hour: prefs.getInt("endTimeHour")!,
                                        minute: prefs.getInt("endTimeMinute")!);
                                    DateTime datetimeToday =
                                        DateTime.fromMillisecondsSinceEpoch(
                                            prefs.getInt('flighTimestamp')!);

                                    if (datetimeToday.day == date.day) {
                                      TimeOfDay startTime = TimeOfDay(
                                          hour: data['startTime']['hour'],
                                          minute: data['startTime']['minute']);
                                      TimeOfDay endTime = TimeOfDay(
                                          hour: data['endTime']['hour'],
                                          minute: data['endTime']['minute']);

                                      print(timeCoincides(<TimeOfDay>[
                                        startTimeCurrent,
                                        endTimeCurrent
                                      ], <TimeOfDay>[
                                        startTime,
                                        endTime
                                      ]));

                                      if (timeCoincides(<TimeOfDay>[
                                        startTimeCurrent,
                                        endTimeCurrent
                                      ], <TimeOfDay>[
                                        startTime,
                                        endTime
                                      ])) {
                                        List<LatLng> route =
                                            data['routes'].map<LatLng>((e) {
                                          return LatLng(
                                              e.latitude, e.longitude);
                                        }).toList();
                                        outRoutes.add(route);
                                      }
                                    }
                                  }

                                  otherPlanLatLngList = outRoutes;
                                  double zoom = mapController.zoom;
                                  List<List<Coordinate>> linesIn =
                                      coordinatesToLines(latLngList, zoom);
                                  for (List<LatLng> outRoute in outRoutes) {
                                    List<List<Coordinate>> linesOut =
                                        coordinatesToLines(outRoute, zoom);

                                    setState(() {
                                      collisionLatLngList.addAll(
                                          getCollisionLatLngList(
                                              linesIn, linesOut, zoom));
                                    });
                                  }
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Please send routes first."),
                                  ),
                                );
                              }
                            },
                            child: const Text("FETCH COLLISIONS"),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      alignment: Alignment(0, 0),
                      child: SizedBox(
                        width: 200,
                        height: 50,
                        child: TextField(
                          controller: _usernameController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: "username",
                            hintStyle: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              )
            ],
          ), // This trailing comma makes auto-formatting nicer for build methods.
          floatingActionButton: FloatingActionButton(
            backgroundColor: floatingColor,
            child: new Icon(
              floatingIcon,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Tap on map to add locations."),
                ),
              );
              setState(() {
                if (!selectionEnabled) {
                  floatingIcon = Icons.cancel_outlined;
                  floatingColor = Colors.red;
                  selectionEnabled = true;
                } else {
                  floatingIcon = Icons.add_location_alt;
                  floatingColor = Colors.blue;
                  selectionEnabled = false;

                  latLngList = [];
                  miniLatLngList = [];
                  droneLocation = 0;
                  collisionLatLngList = [];
                }
              });
            },
          ),
        ),
      );
}
