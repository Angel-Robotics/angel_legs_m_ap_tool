import 'package:flutter/material.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/ota_update/ota_ble_update_page.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';

import '../../device/device_common.dart';

class FindDevicesScreen extends StatelessWidget {
  final Widget? nextPage;

  FindDevicesScreen({this.nextPage});

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
                                    Get.to(
                                      OtaBleUpdatePage(
                                        scanResult: e,
                                      ),
                                    );
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
