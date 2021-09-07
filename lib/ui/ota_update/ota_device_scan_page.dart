import 'package:flutter/material.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/bluetooth_on_off_widget.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/device_common.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/common/find_device_screen.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/ota_update/ota_ble_update_page.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';

class OtaDeviceScanPage extends StatefulWidget {
  @override
  _OtaDeviceScanPageState createState() => _OtaDeviceScanPageState();
}

class _OtaDeviceScanPageState extends State<OtaDeviceScanPage> {
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



