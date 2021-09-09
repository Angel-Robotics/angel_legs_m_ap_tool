import 'package:flutter/material.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/http_ota/network_scan_page.dart';
import 'package:flutter_angel_legs_m_ap_tool/ui/ota_update/ota_device_scan_page.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import 'http_ota/http_ota_update.dart';

class ToolHomePage extends StatefulWidget {
  ToolHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<ToolHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future requestAppPermission() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.storage,
    ].request();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    requestAppPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              onTap: () => Get.to(OtaDeviceScanPage()),
              title: Text("펌웨어 업데이트"),
              subtitle: Text("통신모듈 펌웨어를 업데이트 합니다."),
            ),
            Divider(),
            ListTile(
              onTap: () => Get.to(HttpOtaUpdate()),
              title: Text("웹 펌웨어 업데이트"),
              subtitle: Text("통신모듈 펌웨어를 업데이트 합니다."),
            ),
            Divider(),
            ListTile(
              title: Text("통신모듈 검수"),
              subtitle: Text("통신모듈 펌웨어를 검수합니다."),
            ),
            ListTile(
              onTap: () => Get.to(NetworkScanPage()),
              title: Text("네트워크 검사"),
              subtitle: Text("네트워크 검사"),
            ),
            Divider(),
          ],
        ),
      ),
    );
  }
}
