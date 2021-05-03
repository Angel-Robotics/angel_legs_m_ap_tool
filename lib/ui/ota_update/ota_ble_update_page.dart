import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/percent_indicator.dart';

class OtaBleUpdatePage extends StatefulWidget {
  ScanResult scanResult;

  OtaBleUpdatePage({Key? key, required this.scanResult}) : super(key: key);

  @override
  _OtaBleUpdatePageState createState() => _OtaBleUpdatePageState();
}

class _OtaBleUpdatePageState extends State<OtaBleUpdatePage> {
  bool isDeviceConnected = false;
  bool isUpdateFileRead = false;
  bool isAuthMessagePass = false;
  bool isOtaAuthCompleted = false;
  bool _isOtaProgress = false;

  List<int> otaMessage = [];
  List<int> otaHmac = [];

  TextEditingController _textEditingController = TextEditingController();
  StreamSubscription? _deviceStateStreamSubscription;
  StreamSubscription? _otaAuthStreamSubscription;
  StreamSubscription? _indexSubscription;

  BluetoothDevice? _bluetoothDevice;

  late BluetoothCharacteristic binWriteCharacteristic;
  late BluetoothCharacteristic binSizeWriteCharacteristic;
  late BluetoothCharacteristic indexNotifyCharacteristic;
  late BluetoothCharacteristic otaAuthCharacteristic;

  late Uint8List binDate;
  var chunks = [];
  var chunkSize = 512;
  int totalBinSize = 0;
  num chunksLength = 0;
  String progressText = "";
  String progressTimeText = "";
  double _percent = 0.0;
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
    super.dispose();
  }

  void listenOtaIndexStream() {
    _indexSubscription = indexNotifyCharacteristic.value.listen((event) {
      if (event.length > 0) {
        print(event);
        int _index =
            ((event[3] << 24) & 0xff000000) | ((event[2] << 16) & 0x00ff0000) | ((event[1] << 8) & 0x0000ff00) | (event[0] & 0x000000ff);
        print("Notify index : $_index");

        if (_index == chunksLength.toInt()) {
          print(">>> stop _index == chunksLength.toInt()");
          endTime = DateTime.now().millisecondsSinceEpoch;
          print("총 소요시간: ${endTime - startTime}");

          setState(() {
            _isOtaProgress = false;
            progressTimeText = (endTime - startTime).toString();
          });

        } else {
          binWriteCharacteristic.write(chunks[_index]);
        }
        setState(() {
          _percent = (_index / chunksLength);
          progressText = "$_index / $chunksLength";
        });
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
              Get.snackbar("알림", "인증 성공");
            } else {
              setState(() {
                isAuthMessagePass = false;
                isOtaAuthCompleted = false;
              });
              Get.snackbar("알림", "인증 실패");
            }
          }
        }
        if (event.length == 10) {
          if (otaMessage.length > 0) otaMessage.clear();
          otaMessage.addAll(event);
          var inputList = [];
          _textEditingController.text.runes.forEach((rune) {
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
          var hmacSha256 =
              Hmac(sha1, [0x41, 0x4E, 0x47, 0x45, 0x4C, 0x20, 0x52, 0x4F, 0x42, 0x4F, 0x54, 0x49, 0x43, 0x53, 0x32, 0x31]); // HMAC-SHA256
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
              }
            });
          });

          await otaAuthCharacteristic.setNotifyValue(true);
          await indexNotifyCharacteristic.setNotifyValue(true);

          listenOtaIndexStream();
          listenOtaAuthStream();
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
    print("chunks길이: ${chunks.length}");
    setState(() {
      isUpdateFileRead = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("블루투스 OTA 업데이트"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text("업데이트 파일 선택"),
              subtitle: Text(""),
              onTap: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles();
                if (result != null) {
                  print(result.files.single.name);
                  if (!result.files.single.name!.contains(".bin")) {
                    setState(() {
                      isUpdateFileRead = false;
                    });

                    Get.snackbar("오류", "올바른 파일을 선택해주세요", backgroundColor: Colors.orangeAccent);
                    return;
                  }
                  File file = File(result.files.single.path!);
                  readBinFile(file);
                } else {
                  // User canceled the picker
                }
              },
            ),
            Text("파일 읽기 상태"),
            Container(
              height: 64,
              width: 120,
              child: Center(child: Text("파일 읽기 상태")),
              color: isUpdateFileRead ? Colors.green : Colors.red,
            ),
            Divider(),
            Text("디바이스 상태"),
            Container(
              color: isDeviceConnected ? Colors.green : Colors.grey,
              padding: EdgeInsets.all(16),
              child: Text("연결상태"),
            ),
            Divider(),
            SizedBox(
              height: 120,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textEditingController,
                      maxLength: 20,
                      minLines: 1,
                      maxLines: 1,
                      style: TextStyle(fontSize: 24),
                      decoration: InputDecoration(
                          hintText: "인증 암호 입력",
                          suffixIcon: IconButton(
                            icon: Icon(Icons.clear),
                            onPressed: () {
                              _textEditingController.clear();
                            },
                          )),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: MaterialButton(
                        minWidth: 160,
                        onPressed: _isOtaProgress ? null :() async {
                          if (_textEditingController.text.length > 0) {
                            await otaAuthCharacteristic.write([0x02, 0x00, 0x03]);
                          } else {
                            Get.defaultDialog(content: Text("메세지를 입력하세요"));
                          }
                        },
                        child: Text("인증"),
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text("인증 상태"),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: isAuthMessagePass ? Colors.green : Colors.grey,
                      padding: EdgeInsets.all(16),
                      child: Text("1차"),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                  Expanded(
                    child: Container(
                      color: isOtaAuthCompleted ? Colors.green : Colors.grey,
                      padding: EdgeInsets.all(16),
                      child: Text("2차"),
                    ),
                  ),
                ],
              ),
            ),
            Divider(),
            Text("사전설정"),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: MaterialButton(
                      onPressed: _isOtaProgress ? null :() async {
                        if (isOtaAuthCompleted) {
                          await _bluetoothDevice?.requestMtu(chunkSize);
                        } else {
                          Get.snackbar("인증오류", "인증을 완료해주세요", backgroundColor: Colors.red[100]);
                        }
                      },
                      color: isDeviceConnected ? Colors.blue : Colors.grey,
                      child: Text('설정1'),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                  Expanded(
                    child: MaterialButton(
                      onPressed: _isOtaProgress ? null :() async {
                        if (isOtaAuthCompleted) {
                          if (isUpdateFileRead) {
                            await binSizeWriteCharacteristic.write([
                              (totalBinSize >> 24) & 0xFF,
                              (totalBinSize >> 16) & 0xFF,
                              (totalBinSize >> 8) & 0xFF,
                              (totalBinSize) & 0xFF,
                              (chunksLength.toInt() >> 24) & 0xFF,
                              (chunksLength.toInt() >> 16) & 0xFF,
                              (chunksLength.toInt() >> 8) & 0xFF,
                              (chunksLength.toInt()) & 0xFF,
                            ]);
                          } else {
                            Get.snackbar("알림", "업데이트 파일을 선택해주세요", backgroundColor: Colors.red[100]);
                          }
                        } else {
                          Get.snackbar("인증오류", "인증을 완료해주세요", backgroundColor: Colors.red[100]);
                        }
                      },
                      color: isDeviceConnected ? Colors.blue : Colors.grey,
                      child: Text('설정2'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: MaterialButton(
                  minWidth: MediaQuery.of(context).size.width,
                  height: 72,
                  child: Text("보내기"),
                  color: Colors.blue,
                  onPressed: !_isOtaProgress ? () async {

                    if (isOtaAuthCompleted && isUpdateFileRead) {
                      if(!_isOtaProgress){
                        startTime = DateTime.now().millisecondsSinceEpoch;
                        await binWriteCharacteristic.write(chunks[0]);
                      }
                      _isOtaProgress = true;
                    } else {
                      Get.snackbar("인증오류", "인증을 완료해주세요", backgroundColor: Colors.red[100]);
                    }
                  }: null) ,
            ),
            Padding(
              padding: EdgeInsets.all(15.0),
              child: new CircularPercentIndicator(
                radius: 240.0,
                lineWidth: 12.0,
                percent: _percent,
                center: Text(
                  "${(_percent * 100).toStringAsFixed(1)} %",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                progressColor: Colors.green,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "Now/Total: $progressText 코드 조각",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    "소요시간(ms): $progressTimeText ms (${chunks.length} 코드 조각) ",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    "-> 분: ${((endTime - startTime) ~/ 1000) ~/ 60} 분",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            Divider(),
            MaterialButton(
              onPressed: () async {
                if (isDeviceConnected) {
                  await _bluetoothDevice?.disconnect();
                  isAuthMessagePass = false;
                  Get.back();
                }
              },
              color: isDeviceConnected ? Colors.red : Colors.grey,
              child: Text('연결종료'),
            ),
          ],
        ),
      ),
    );
  }
}