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

  void listenOtaIndexStream() {
    _indexSubscription = indexNotifyCharacteristic.value.listen((event) async {
      if (event.length > 0) {
        int _index = ((event[3] << 24) & 0xff000000) |
            ((event[2] << 16) & 0x00ff0000) |
            ((event[1] << 8) & 0x0000ff00) |
            (event[0] & 0x000000ff);
        print("Notify index : $_index");

        if (_index == chunksLength.toInt()) {
          print(">>> stop _index == chunksLength.toInt()");
          endTime = DateTime.now().millisecondsSinceEpoch;
          print("총 소요시간: ${endTime - startTime}");

          setState(() {
            _isOtaProgress = false;
            progressTimeText = (endTime - startTime).toString();
          });

          _bluetoothDevice?.requestMtu(20);
          _bluetoothDevice?.disconnect().then((value) {
            showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  return WillPopScope(
                    onWillPop: () async => false,
                    child: AlertDialog(
                      title: Text("알림"),
                      content: Text("OTA 업데이트 작업이 완료되었습니다."),
                      actions: [
                        TextButton(
                            onPressed: () async {
                              await _deviceStateStreamSubscription?.cancel();
                              await _otaAuthStreamSubscription?.cancel();
                              await _indexSubscription?.cancel();
                              await _otaControlPointSubscription?.cancel();
                              Navigator.of(context).pop();
                              Navigator.of(context).pop();
                            },
                            child: Text("확인"))
                      ],
                    ),
                  );
                });
            // Get.back();
          });
        } else {
          try {
            await Future.delayed(Duration(milliseconds: 200));
            binWriteCharacteristic.write(chunks[_index], withoutResponse: false);
          } catch (e) {
            print("[Error] ${e.toString()}");
            binWriteCharacteristic.write(chunks[_index], withoutResponse: true);
          }
        }

        _percent.value = (_index / chunksLength);
        progressText.value = "$_index / $chunksLength";
      }
    });
  }

  void listenOtaAuthStream() {
    _otaAuthStreamSubscription = otaAuthCharacteristic.value.listen((event) async {
      print(">>> set _otaAuthStreamSubscription");

      if (event.length > 0) {
        print(">>> $event");
        if (event.length == 3) {
          if (event[0] == 0x02 && event[2] == 0x03) {
            if (event[1] == 0x11) {
              setState(() {
                isOtaAuthCompleted = true;
              });
              Get.snackbar("알림", "인증 성공", backgroundColor: Colors.green);
            } else {
              setState(() {
                isAuthMessagePass = false;
                isOtaAuthCompleted = false;
              });
              Get.snackbar("알림", "인증 실패", backgroundColor: Colors.red);
            }
          }
        }
        if (event.length == 10) {
          if (otaMessage.length > 0) otaMessage.clear();
          otaMessage.addAll(event);
          var inputList = [];
          _ssidTextEditingController.text.runes.forEach((rune) {
            inputList.add(rune);
          });
          otaMessage.forEach((element) {
            print(element.toRadixString(16));
          });
          isAuthMessagePass = listEquals(otaMessage, inputList);
          print(isAuthMessagePass);
          if (isAuthMessagePass) {
            await otaAuthCharacteristic.write([0x02, 0x01, 0x03]);
          } else {
            Get.snackbar("오류", "입력한 메시지가 올바르지 않습니다.", backgroundColor: Colors.orangeAccent);
            return;
          }
        } else if (event.length == 20) {
          if (otaHmac.length > 0) otaHmac.clear();
          otaHmac.addAll(event);
          var hmacSha256 = Hmac(sha1, [
            0x41,
            0x4E,
            0x47,
            0x45,
            0x4C,
            0x20,
            0x52,
            0x4F,
            0x42,
            0x4F,
            0x54,
            0x49,
            0x43,
            0x53,
            0x32,
            0x31
          ]); // HMAC-SHA256
          var digest = hmacSha256.convert(otaMessage);
          print("HMAC digest as bytes: ${digest.bytes}");
          print("HMAC digest as hex string: $digest");
          await otaAuthCharacteristic.write(digest.bytes);
        }
      }
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    _bluetoothDevice = widget.scanResult.device;
    _deviceStateStreamSubscription = widget.scanResult.device.state.listen((event) {
      if (event == BluetoothDeviceState.disconnected) {
        print(">>> BluetoothDeviceState.disconnected");
        if (!isDeviceConnected) connectBluetoothDevice();
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

          listenOtaIndexStream();
          listenOtaAuthStream();
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
                }
              }
            }
          });
        });
      }
    });
  }

  Future<void> readBinFile(File file) async {
    Uint8List tmp = await file.readAsBytes();
    print("파일 읽은 길이 : ${tmp.length}");
    binDate = tmp;
    var len = binDate.length;
    totalBinSize = len;

    for (var i = 0; i < len; i += chunkSize) {
      var end = (i + chunkSize < len) ? i + chunkSize : len;
      chunks.add(binDate.sublist(i, end));
    }
    print(chunks);
    chunksLength = chunks.length;
    print("chunks 길이: ${chunks.length}");
    setState(() {
      isUpdateFileRead = true;
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
          child: Column(
        children: [
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
                      _ssidTextEditingController.text.runes.forEach((element) {
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
                      otaWifiControlCharacteristic.write([0x02, 0x02, ...data, 0x03]);
                    }
                  },
                  child: Text("PWD 전달")),
            ],
          ),
          ElevatedButton(
              onPressed: () {
                otaWifiControlCharacteristic.write([0x02, 0x02, 0x01, 0x03]);
              },
              child: Text("PWD 전달")),
        ],
      )),
    );
  }
}
