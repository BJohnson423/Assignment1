import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path/path.dart' as Path;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

// This tutorial could help you understand more about building an app with Flutter.
// https://codelabs.developers.google.com/codelabs/flutter-codelab-first#0
// It is recommended but not required.

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMU Data Recording',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // TODO: Add a boolean variable, recording, to the help indicate whether we are recording the sensor data.
  bool recording = false;

  // TODO: Add all variables for retrieving sensor data events, update times, and intervals
  UserAccelerometerEvent? _userAccelerometerEvent;
  AccelerometerEvent? _accelerometerEvent;
  GyroscopeEvent? _gyroscopeEvent;
  MagnetometerEvent? _magnetometerEvent;

  // TODO: Initiate _streamSubscriptions to retrieve all StreamSubscriptions in an array.
  // https://pub.dev/documentation/sensors_plus_platform_interface/latest/sensors_plus_platform_interface/AccelerometerEvent-class.html
  // using this site to help through the dart commands
  final List<StreamSubscription<dynamic>> _streamSubscriptions = [];

  // TODO: Initiate a DatabaseHelper instance.
  // DatabaseHelper class is at the end of this file and requires your implementation.
  // waiting till end. comback to verify. *****
  final dbHelper = DatabaseHelper.instance;
  int _savedSamples = 0;

  @override
  Widget build(BuildContext context) {
    // return a Scaffold object for the UI elements.
    return Scaffold(
      appBar: AppBar(title: const Text('IMU Sensor Data Recording')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              recording ? Icons.sensors : Icons.sensors_off,
              size: 80,
              color: recording ? Colors.red : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              recording ? 'Recording Active' : 'Recording Stopped',
              //tabs accidently add code sometimes.
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: recording ? Colors.red : Colors.grey,
              ),
            ),
            Text('Samples saved this session: $_savedSamples'),
            const SizedBox(height: 30),

            if (_accelerometerEvent != null)
              Text(
                'Accelerometer: x=${_accelerometerEvent!.x.toStringAsFixed(2)} | '
                'y=${_accelerometerEvent!.y.toStringAsFixed(2)} |'
                'z=${_accelerometerEvent!.z.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 16),
              ),
            SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () async {
                if (recording) {
                  setState(() {
                    recording = false;
                  });
                  await stopRecording();
                } else {
                  setState(() {
                    recording = true;
                    _savedSamples = 0;
                  });
                  startRecording();
                }
              },

              icon: Icon(recording ? Icons.stop : Icons.play_arrow),
              label: Text(recording ? 'Stop Recording' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await dbHelper.exportDatabase();
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Database export failed: $error')),
                  );
                }
              },
              icon: Icon(Icons.share),
              label: Text('Export IMUDatabase'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> stopRecording() async {
    await Future.wait(
      _streamSubscriptions.map((subscription) {
        return subscription.cancel();
      }),
    );
    _streamSubscriptions.clear();
  }

  void startRecording() {
    _streamSubscriptions.add(
      userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
        if (!mounted) return;
        setState(() {
          _userAccelerometerEvent = event;
        });
      }),
    );

    _streamSubscriptions.add(
      accelerometerEventStream().listen((AccelerometerEvent event) {
        if (!mounted) return;
        setState(() {
          _accelerometerEvent = event;
        });
        unawaited(_saveCurrentSensorData());
      }),
    );

    _streamSubscriptions.add(
      gyroscopeEventStream().listen((GyroscopeEvent event) {
        if (!mounted) return;
        setState(() {
          _gyroscopeEvent = event;
        });
      }),
    );

    _streamSubscriptions.add(
      magnetometerEventStream().listen((MagnetometerEvent event) {
        if (!mounted) return;
        setState(() {
          _magnetometerEvent = event;
        });
      }),
    );
  }

  Future<void> _saveCurrentSensorData() async {
    if (!recording) return;

    final imuData = ImuData(
      userAccelX: _userAccelerometerEvent?.x ?? 0.0,
      userAccelY: _userAccelerometerEvent?.y ?? 0.0,
      userAccelZ: _userAccelerometerEvent?.z ?? 0.0,
      accelX: _accelerometerEvent?.x ?? 0.0,
      accelY: _accelerometerEvent?.y ?? 0.0,
      accelZ: _accelerometerEvent?.z ?? 0.0,
      gyroX: _gyroscopeEvent?.x ?? 0.0,
      gyroY: _gyroscopeEvent?.y ?? 0.0,
      gyroZ: _gyroscopeEvent?.z ?? 0.0,
      magX: _magnetometerEvent?.x ?? 0.0,
      magY: _magnetometerEvent?.y ?? 0.0,
      magZ: _magnetometerEvent?.z ?? 0.0,
      timestamp: DateTime.now().toIso8601String(),
    );

    try {
      await dbHelper.insertImuData(imuData);
      if (mounted) {
        setState(() {
          _savedSamples++;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        recording = false;
      });
      await stopRecording();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saving sensor data failed: $error')),
      );
    }
  }
}

// Define a class with all desired variables to store in the table
class ImuData {
  // TODO: Define all variables in this class here
  final double userAccelX;
  final double userAccelY;
  final double userAccelZ;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double magX;
  final double magY;
  final double magZ;

  final String timestamp;

  // Define the initiation of the class instance
  // the visual studio filled this in from the variables. added required myself.
  ImuData({
    required this.userAccelX,
    required this.userAccelY,
    required this.userAccelZ,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.magX,
    required this.magY,
    required this.magZ,
    required this.timestamp,
  });

  // TODO: Convert a IMU data into a Map. The keys must correspond to the names of the
  // columns in the database. assisted by visual studio.
  Map<String, Object?> toMap() {
    return {
      'userAccelX': userAccelX,
      'userAccelY': userAccelY,
      'userAccelZ': userAccelZ,
      'accelX': accelX,
      'accelY': accelY,
      'accelZ': accelZ,
      'gyroX': gyroX,
      'gyroY': gyroY,
      'gyroZ': gyroZ,
      'magX': magX,
      'magY': magY,
      'magZ': magZ,
      'timestamp': timestamp,
    };
  }
}

// Define a DatabaseHelper class
class DatabaseHelper {
  // TODO: create static variables to store to the same database
  // and construct a global/static DatabaseHelper instance
  static const _databaseName = "IMUDatabase.db";
  static const _databaseVersion = 1;
  static const table = 'imu_table';
  static const columnId = '_id';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  // TODO: Define the function to get all items from database
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  //throw UnimplementedError('Database initialization is not implemented.');

  // TODO: Open the database and create the table if it doesn't exist.
  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = Path.join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  // TODO: SQL code to create the database table.
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          userAccelX REAL NOT NULL,
          userAccelY REAL NOT NULL,
          userAccelZ REAL NOT NULL,
          accelX REAL NOT NULL,
          accelY REAL NOT NULL,
          accelZ REAL NOT NULL,
          gyroX REAL NOT NULL,
          gyroY REAL NOT NULL,
          gyroZ REAL NOT NULL,
          magX REAL NOT NULL,
          magY REAL NOT NULL,
          magZ REAL NOT NULL,
          timestamp TEXT NOT NULL
      )
    ''');
  }

  // TODO: Method to insert IMU data into the database.
  Future<void> insertImuData(ImuData imuData) async {
    Database db = await instance.database;
    await db.insert(
      table,
      imuData.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // TODO: Write a function to export the database using Share.shareXFiles()
  Future<void> exportDatabase() async {
    await database;
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = Path.join(documentsDirectory.path, _databaseName);
    // share depreciated and using shareplus instead. https://pub.dev/packages/share_plus
    final dbFile = File(path);
    await Share.shareXFiles([
      XFile(dbFile.path),
    ], text: 'Exported IMU Database');
  }
}
