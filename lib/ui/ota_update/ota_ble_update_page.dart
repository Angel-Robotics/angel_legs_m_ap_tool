import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_angel_legs_m_ap_tool/device/ota_keys.dart';
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
  bool _isSettingCompleted = false;

  List<int> otaMessage = [];
  List<int> otaHmac = [];

  TextEditingController _textEditingController = TextEditingController();
  StreamSubscription? _deviceStateStreamSubscription;
  StreamSubscription? _otaAuthStreamSubscription;
  StreamSubscription? _indexSubscription;
  StreamSubscription? _otaControlPointSubscription;

  BluetoothDevice? _bluetoothDevice;

  late BluetoothCharacteristic binWriteCharacteristic;
  late BluetoothCharacteristic binSizeWriteCharacteristic;
  late BluetoothCharacteristic indexNotifyCharacteristic;
  late BluetoothCharacteristic otaAuthCharacteristic;

  late BluetoothCharacteristic swRevisionCharacteristic;
  late BluetoothCharacteristic fwRevisionCharacteristic;

  late Uint8List binDate;
  String fwVersion = "";
  String swVersion = "";

  var chunkSize = 512;
  var chunks = [];
  int totalBinSize = 0;
  num chunksLength = 0;
  ValueNotifier<String> progressText = ValueNotifier("");
  String progressTimeText = "";
  ValueNotifier<double> _percent = ValueNotifier(0.0);
  int startTime = 0;
  int endTime = 0;

  Stopwatch stopwatch = Stopwatch();
  double sendPeriodic = 100;

  Timer? elapseTimer;
  String elapseTimeText = "";

  Future connectBluetoothDevice() async {
    await widget.scanResult.device.connect();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    elapseTimer?.cancel();

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
          print("??? ????????????: ${endTime - startTime}");

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
                      title: Text("??????"),
                      content: Text("OTA ???????????? ????????? ?????????????????????."),
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
                            child: Text("??????"))
                      ],
                    ),
                  );
                });
            // Get.back();
          });
        } else {
          try {
            await Future.delayed(Duration(milliseconds: sendPeriodic.toInt()));
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
              Get.snackbar("??????", "?????? ??????", backgroundColor: Colors.green);
            } else {
              setState(() {
                isAuthMessagePass = false;
                isOtaAuthCompleted = false;
              });
              Get.snackbar("??????", "?????? ??????", backgroundColor: Colors.red);
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
            Get.snackbar("??????", "????????? ???????????? ???????????? ????????????.", backgroundColor: Colors.orangeAccent);
            return;
          }
        } else if (event.length == 20) {
          if (otaHmac.length > 0) otaHmac.clear();
          otaHmac.addAll(event);
          var hmacSha256 = Hmac(sha1, OtaKeys.hmacKey); // HMAC-SHA256
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
              } else if (char.uuid.toString().toUpperCase() == "00002A25-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                // binWriteCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "00002A29-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                // binWriteCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "00002A26-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                // binWriteCharacteristic = char;
                fwRevisionCharacteristic = char;
              } else if (char.uuid.toString().toUpperCase() == "00002A28-0000-1000-8000-00805f9b34fb".toUpperCase()) {
                // binWriteCharacteristic = char;
                swRevisionCharacteristic = char;
              }
            });
          });

          fwVersion = String.fromCharCodes(await fwRevisionCharacteristic.read());
          swVersion = String.fromCharCodes(await swRevisionCharacteristic.read());
          setState(() {});

          await otaAuthCharacteristic.setNotifyValue(true);
          await indexNotifyCharacteristic.setNotifyValue(true);
          await binSizeWriteCharacteristic.setNotifyValue(true);

          listenOtaIndexStream();
          listenOtaAuthStream();

          _otaControlPointSubscription = binSizeWriteCharacteristic.value.listen((event) {
            if (event.length > 0) {
              if (event[0] == 0x02 && event[3] == 0x03) {
                if (event[1] == 0x00) {
                  if (event[2] == 0x11) {
                    Get.snackbar("??????", "?????? ?????? ??????", backgroundColor: Colors.green);
                    setState(() {
                      _isSettingCompleted = true;
                    });
                  }
                } else if (event[1] == 0x01) {
                  if (event[2] == 0x01) {
                    Get.snackbar("??????", "???????????? ?????? ??????", backgroundColor: Colors.green);
                  } else if (event[2] == 0x02) {
                    Get.snackbar("??????", "???????????? ?????? ??????", backgroundColor: Colors.red);
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
    print("file.path: ${file.path}");
    Uint8List tmp = await file.readAsBytes();
    print("?????? ?????? ?????? : ${tmp.length}");
    binDate = tmp;
    var len = binDate.length;
    totalBinSize = len;

    for (var i = 0; i < len; i += chunkSize) {
      var end = (i + chunkSize < len) ? i + chunkSize : len;
      chunks.add(binDate.sublist(i, end));
    }

    print("chunks: $chunks");
    chunksLength = chunks.length;
    print("chunks ??????: $chunksLength");
    setState(() {
      isUpdateFileRead = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("???????????? OTA ????????????"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text("?????? BT MAC : ${widget.scanResult.device.id}"),
                ),
                ListTile(
                  title: Text("FW ??????: ${fwVersion}"),
                ),
                ListTile(
                  title: Text("SW ??????: ${swVersion}"),
                ),
                Divider(
                  color: Colors.black,
                ),
                _isOtaProgress
                    ? SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            title: Text("???????????? ?????? ??????"),
                            subtitle: Text(""),
                            trailing: Icon(Icons.keyboard_arrow_right),
                            onTap: () async {
                              FilePickerResult? result = await FilePicker.platform.pickFiles();
                              if (result != null) {
                                print("file name: ${result.files.single.name}");
                                if (!result.files.single.name.contains(".bin")) {
                                  setState(() {
                                    isUpdateFileRead = false;
                                  });
                                  Get.snackbar("??????", "????????? ????????? ??????????????????", backgroundColor: Colors.orangeAccent);
                                  return;
                                }
                                chunks = [];
                                totalBinSize = 0;
                                chunksLength = 0;
                                File file = File(result.files.single.path ?? "");
                                readBinFile(file);
                              } else {
                                // User canceled the picker
                              }
                            },
                          ),
                          Text("??? ?????????: $totalBinSize"),
                          Text("??? Chunk: $chunksLength"),
                          Divider(
                            color: Colors.black,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text("?????? ?????? ??????"),
                                    Container(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: Text("?????? ?????? ??????")),
                                      color: isUpdateFileRead ? Colors.green : Colors.red,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 16,
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text("???????????? ??????"),
                                    Container(
                                      color: isDeviceConnected ? Colors.green : Colors.grey,
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: Text("????????????")),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                          Divider(
                            color: Colors.grey,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
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
                                      obscureText: true,
                                      decoration: InputDecoration(
                                          hintText: "?????? ?????? ??????",
                                          suffixIcon: IconButton(
                                            icon: Icon(Icons.clear),
                                            onPressed: () {
                                              _textEditingController.clear();
                                            },
                                          )),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 16,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: MaterialButton(
                                        onPressed: _isOtaProgress
                                            ? null
                                            : () async {
                                                if (_textEditingController.text.length > 0) {
                                                  await otaAuthCharacteristic.write([0x02, 0x00, 0x03]);
                                                } else {
                                                  Get.defaultDialog(content: Text("???????????? ???????????????"));
                                                }
                                              },
                                        child: Text(
                                          "??????",
                                          style: TextStyle(fontSize: 24),
                                        ),
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Text("?????? ??????"),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    color: isAuthMessagePass ? Colors.green : Colors.grey,
                                    padding: EdgeInsets.all(16),
                                    child: Text("1???"),
                                  ),
                                ),
                                SizedBox(
                                  width: 24,
                                ),
                                Expanded(
                                  child: Container(
                                    color: isOtaAuthCompleted ? Colors.green : Colors.grey,
                                    padding: EdgeInsets.all(16),
                                    child: Text("2???"),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            color: Colors.black,
                          ),
                          Text("????????????"),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: MaterialButton(
                                    padding: EdgeInsets.all(16),
                                    onPressed: _isOtaProgress || _isSettingCompleted
                                        ? null
                                        : () async {
                                            if (isOtaAuthCompleted) {
                                              if (isUpdateFileRead) {
                                                await _bluetoothDevice?.requestMtu(chunkSize);
                                                await Future.delayed(Duration(seconds: 1));
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
                                                Get.snackbar("??????", "???????????? ????????? ??????????????????", backgroundColor: Colors.red[100]);
                                              }
                                            } else {
                                              Get.snackbar("????????????", "????????? ??????????????????", backgroundColor: Colors.red[100]);
                                            }
                                          },
                                    color: isDeviceConnected ? Colors.brown : Colors.grey,
                                    child: Text(
                                      'OTA ??????',
                                      style: TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 24,
                          ),
                          Text("????????????"),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                    min: 0,
                                    max: 1000,
                                    divisions: 20,
                                    value: sendPeriodic,
                                    onChanged: (v) {
                                      setState(() {
                                        sendPeriodic = v;
                                      });
                                    }),
                              ),
                              SizedBox(
                                width: 24,
                              ),
                              SizedBox(width: 24, child: Text("${sendPeriodic}ms"))
                            ],
                          ),
                          SizedBox(
                            height: 24,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: MaterialButton(
                                minWidth: MediaQuery.of(context).size.width,
                                height: 72,
                                child: Text(
                                  "?????????",
                                  style: TextStyle(fontSize: 24),
                                ),
                                color: _isOtaProgress ? Colors.grey : Colors.blue,
                                onPressed: !_isOtaProgress
                                    ? () async {
                                        if (isOtaAuthCompleted && isUpdateFileRead) {
                                          if (!_isOtaProgress) {
                                            startTime = DateTime.now().millisecondsSinceEpoch;
                                            await binWriteCharacteristic.write(chunks[0]);
                                            stopwatch.stop();
                                            stopwatch.reset();
                                            stopwatch.start();
                                            elapseTimer = Timer.periodic(Duration(seconds: 1), (timer) {
                                              setState(() {
                                                elapseTimeText = stopwatch.elapsedMilliseconds.toString();
                                              });
                                            });
                                          }
                                          setState(() {
                                            _isOtaProgress = true;
                                          });
                                        } else {
                                          Get.snackbar("????????????", "????????? ??????????????????", backgroundColor: Colors.red[100]);
                                        }
                                      }
                                    : null),
                          ),
                        ],
                      ),
                _isOtaProgress
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text("??? ?????????: $totalBinSize"),
                          Text("??? Chunk: $chunksLength"),
                          Padding(
                            padding: EdgeInsets.all(15.0),
                            child: Center(
                                child: ValueListenableBuilder<double>(
                              builder: (context, value, child) {
                                return CircularPercentIndicator(
                                  radius: 240.0,
                                  lineWidth: 24.0,
                                  circularStrokeCap: CircularStrokeCap.round,
                                  percent: value,
                                  progressColor: Colors.green,
                                  center: Text(
                                    "${(value * 100).toStringAsFixed(1)} %",
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                              valueListenable: _percent,
                            )),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: ValueListenableBuilder(
                              valueListenable: progressText,
                              builder: (context, value, child) {
                                return Text(
                                  "Now/Total: $value ?????? ??????",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              "???????????? : $elapseTimeText ms ",
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  "????????????(ms): $progressTimeText ms",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  "-> ???: ${((endTime - startTime) ~/ 1000) ~/ 60} ???",
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : SizedBox.shrink(),
                Divider(
                  color: Colors.black,
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: MaterialButton(
                    minWidth: MediaQuery.of(context).size.width,
                    onPressed: () async {
                      if (isDeviceConnected) {
                        await _deviceStateStreamSubscription?.cancel();
                        await _otaAuthStreamSubscription?.cancel();
                        await _indexSubscription?.cancel();
                        await _otaControlPointSubscription?.cancel();
                        await _bluetoothDevice?.disconnect();
                        setState(() {
                          isDeviceConnected = false;
                          isUpdateFileRead = false;
                          isAuthMessagePass = false;
                          isOtaAuthCompleted = false;
                          _isOtaProgress = false;
                        });
                        Get.back();
                      }
                    },
                    color: isDeviceConnected ? Colors.red : Colors.grey,
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '????????????',
                      style: TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
