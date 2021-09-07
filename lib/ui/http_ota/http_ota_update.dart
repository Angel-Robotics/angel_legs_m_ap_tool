import 'package:flutter/material.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/bluetooth_on_off_widget.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/device_common.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/find_device_screen.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';

import 'http_ota_setting_page.dart';

class HttpOtaUpdate extends StatefulWidget {
  const HttpOtaUpdate({Key? key}) : super(key: key);

  @override
  _HttpOtaUpdateState createState() => _HttpOtaUpdateState();
}

class _HttpOtaUpdateState extends State<HttpOtaUpdate> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<BluetoothState>(
          stream: FlutterBlue.instance.state,
          initialData: BluetoothState.unknown,
          builder: (c, snapshot) {
            final state = snapshot.data;
            if (state == BluetoothState.on) {
              return FindDevicesScreen();
            }
            return BluetoothOffScreen(state: state);
          }),
    );
  }
}

class FindDevicesScreen extends StatelessWidget {
  FindDevicesScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () => FlutterBlue.instance.startScan(timeout: Duration(seconds: 4)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(Duration(seconds: 2)).asyncMap((_) => FlutterBlue.instance.connectedDevices),
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data!
                      .map((d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text(d.id.toString()),
                            trailing: StreamBuilder<BluetoothDeviceState>(
                              stream: d.state,
                              initialData: BluetoothDeviceState.disconnected,
                              builder: (c, snapshot) {
                                if (snapshot.data == BluetoothDeviceState.connected) {
                                  return ElevatedButton(onPressed: () {}, child: Text('OPEN'));
                                }
                                return Text(snapshot.data.toString());
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBlue.instance.scanResults,
                initialData: [],
                builder: (c, snapshot) => Column(
                    children: snapshot.data!
                        .where((element) => element.device.name == DeviceCommon.DEVICE_NAME)
                        .toList()
                        .map((e) => Column(
                              children: [
                                ListTile(
                                  onTap: () {
                                    Get.to(HttpOtaSettingPage(scanResult: e));
                                  },
                                  title: Text(e.device.name == "" ? "unknown device" : e.device.name),
                                  subtitle: Text(e.rssi.toString()),
                                  trailing: Text(e.device.id.id.toString()),
                                ),
                                Divider(
                                  color: Colors.grey,
                                ),
                              ],
                            ))
                        .toList()),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data!) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              onPressed: () => FlutterBlue.instance.stopScan(),
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                onPressed: () => FlutterBlue.instance.startScan(timeout: Duration(seconds: 4)));
          }
        },
      ),
    );
  }
}
