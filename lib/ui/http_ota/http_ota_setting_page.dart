import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import 'network_scan_page.dart';

class HttpOtaSettingPage extends StatefulWidget {
  ScanResult scanResult;

  HttpOtaSettingPage({Key? key, required this.scanResult}) : super(key: key);

  @override
  _HttpOtaSettingPageState createState() => _HttpOtaSettingPageState();
}

class _HttpOtaSettingPageState extends State<HttpOtaSettingPage> {
  bool isDeviceConnected = false;
  bool isUpdateFileRead = false;
  bool isAuthMessagePass = false;
  bool isOtaAuthCompleted = false;
  bool _isOtaProgress = false;
  bool _isSettingCompleted = false;

  List<int> otaMessage = [];
  List<int> otaHmac = [];

  TextEditingController _ssidTextEditingController = TextEditingController();
  TextEditingController _pwdTextEditingController = TextEditingController();
  StreamSubscription? _deviceStateStreamSubscription;
  StreamSubscription? _otaAuthStreamSubscription;
  StreamSubscription? _indexSubscription;
  StreamSubscription? _otaControlPointSubscription;
  BluetoothDevice? _bluetoothDevice;

  late BluetoothCharacteristic binWriteCharacteristic;
  late BluetoothCharacteristic binSizeWriteCharacteristic;
  late BluetoothCharacteristic indexNotifyCharacteristic;
  late BluetoothCharacteristic otaAuthCharacteristic;
  late BluetoothCharacteristic otaWifiControlCharacteristic;

  late Uint8List binDate;
  var chunks = [];
  var chunkSize = 512;
  int totalBinSize = 0;
  num chunksLength = 0;
  ValueNotifier<String> progressText = ValueNotifier("");
  String progressTimeText = "";
  ValueNotifier<double> _percent = ValueNotifier(0.0);
  int startTime = 0;
  int endTime = 0;
  Map<String, String> wifiInfo = Map();

  Future connectBluetoothDevice() async {
    await widget.scanResult.device.connect();
  }

  @override
  void dispose() {
    // TODO: implement dispose

    widget.scanResult.device.disconnect();
    _deviceStateStreamSubscription?.cancel();
    _otaAuthStreamSubscription?.cancel();
    _indexSubscription?.cancel();
    _otaControlPointSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getNetworkInfo().then((value) {
      setState(() {
        wifiInfo = value;
        _ssidTextEditingController.text = wifiInfo['wifiName']?.trim() ?? "";
      });
    });
    _bluetoothDevice = widget.scanResult.device;
    _deviceStateStreamSubscription = widget.scanResult.device.state.listen((event) {
      if (event == BluetoothDeviceState.disconnected) {
        print(">>> BluetoothDeviceState.disconnected");

        if (!isDeviceConnected) connectBluetoothDevice();
        if (isDeviceConnected) {
          Get.defaultDialog(title: "연결이 끊어졌습니다.");
        }
        setState(() {
          isDeviceConnected = false;
        });
      } else if (event == BluetoothDeviceState.connected) {
        print(">>> BluetoothDeviceState.connected");
        setState(() {
          isDeviceConnected = true;
        });
        _bluetoothDevice?.discoverServices().then((services) async {
          services.forEach((service) {
            service.characteristics.forEach((char) {
              print(char.uuid.toString());

              if (char.uuid.toString().toUpperCase() == "0000FFA3-0000-1000-8000-00805F9B34FB") {
                otaAuthCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "0000FFA0-0000-1000-8000-00805F9B34FB") {
                binSizeWriteCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "0000FFA1-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                indexNotifyCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "0000FFA2-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                binWriteCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "0000FFA4-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                otaWifiControlCharacteristic = char;
              }
            });
          });

          await otaAuthCharacteristic.setNotifyValue(true);
          await indexNotifyCharacteristic.setNotifyValue(true);
          await binSizeWriteCharacteristic.setNotifyValue(true);
          await otaWifiControlCharacteristic.setNotifyValue(true);

          Get.snackbar("알림", "설정 준비 완료", backgroundColor: Colors.green);

          setState(() {
            _isSettingCompleted = true;
          });

          _otaControlPointSubscription = binSizeWriteCharacteristic.value.listen((event) {
            if (event.length > 0) {
              if (event[0] == 0x02 && event[3] == 0x03) {
                if (event[1] == 0x00) {
                  if (event[2] == 0x11) {
                    Get.snackbar("알림", "준비 설정 완료", backgroundColor: Colors.green);
                    setState(() {
                      _isSettingCompleted = true;
                    });
                  }
                } else if (event[1] == 0x01) {
                  if (event[2] == 0x01) {
                    Get.snackbar("알림", "업데이트 처리 완료", backgroundColor: Colors.green);
                  } else if (event[2] == 0x02) {
                    Get.snackbar("알림", "업데이트 오류 발생", backgroundColor: Colors.red);
                  }
                } else if (event[1] == 0x02) {
                  if (event[2] == 0x21) {
                    Get.snackbar("알림", "SSID 길이 오류 - 다시시도", backgroundColor: Colors.red);
                  } else if (event[2] == 0x31) {
                    Get.snackbar("알림", "비밀번호 길이 오류 - 다시시도", backgroundColor: Colors.red);
                  }
                  else if (event[2] == 0x22) {
                    Get.snackbar("알림", "SSID 설정 완료", backgroundColor: Colors.green);
                  }
                  else if (event[2] == 0x32) {
                    Get.snackbar("알림", "비밀번호 설정 완료", backgroundColor: Colors.green);
                  }
                }
              }
            }
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("웹 OTA 업데이트"),
      ),
      body: SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Column(
                children: wifiInfo.entries
                    .map((e) => ListTile(
                          title: Text("${e.value}"),
                          subtitle: Text("${e.key}"),
                        ))
                    .toList()),
            Divider(
              color: Colors.black,
            ),
            !_isSettingCompleted
                ? Center(
                    child: CircularProgressIndicator(),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ssidTextEditingController,
                            ),
                          ),
                          ElevatedButton(
                              onPressed: () {
                                if (_ssidTextEditingController.text.isNotEmpty) {
                                  String tmp = _ssidTextEditingController.text;
                                  List<int> data = [];
                                  _ssidTextEditingController.text.trim().runes.forEach((element) {
                                    data.add(element);
                                  });
                                  print(data);
                                  otaWifiControlCharacteristic.write([0x02, 0x02, ...data, 0x03]);
                                }
                              },
                              child: Text("SSID 전달")),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pwdTextEditingController,
                            ),
                          ),
                          ElevatedButton(
                              onPressed: () {
                                if (_pwdTextEditingController.text.isNotEmpty) {
                                  String tmp = _pwdTextEditingController.text;
                                  List<int> data = [];
                                  _pwdTextEditingController.text.runes.forEach((element) {
                                    data.add(element);
                                  });
                                  print(data);
                                  otaWifiControlCharacteristic.write([0x02, 0x03, ...data, 0x03]);
                                }
                              },
                              child: Text("PWD 전달")),
                        ],
                      ),
                      SizedBox(
                        height: 24,
                      ),
                      Row(
                        children: [
                          ElevatedButton(
                              onPressed: () {
                                otaWifiControlCharacteristic.write([0x02, 0x01, 0x01, 0x03]);
                              },
                              child: Text("OTA 켜기")),
                          SizedBox(
                            width: 16,
                          ),
                          ElevatedButton(
                              onPressed: () {
                                otaWifiControlCharacteristic.write([0x02, 0x01, 0x02, 0x03]);
                              },
                              child: Text("OTA 끄기")),
                        ],
                      ),
                      SizedBox(
                        height: 24,
                      ),
                      Row(
                        children: [
                          ElevatedButton(
                              onPressed: () {
                                otaWifiControlCharacteristic.write([0x02, 0x04, 0x01, 0x03]);
                              },
                              child: Text("OTA 메모리 초기화")),
                          SizedBox(
                            width: 16,
                          ),
                          ElevatedButton(
                              onPressed: () {
                                otaWifiControlCharacteristic.write([0x02, 0xFF, 0x01, 0x03]);
                              },
                              child: Text("OTA EEPROM 디버깅")),
                        ],
                      ),
                    ],
                  )
          ],
        ),
      )),
    );
  }
}
