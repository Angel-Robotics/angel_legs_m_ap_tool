import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lan_scanner/lan_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';

Future<Map<String, String>> getNetworkInfo() async {
  Map<String, String> result = Map();
  final info = NetworkInfo();
  var wifiName = await info.getWifiName(); // FooNetwork
  var wifiBSSID = await info.getWifiBSSID(); // 11:22:33:44:55:66
  var wifiIP = await info.getWifiIP(); // 192.168.1.43
  var wifiIPv6 = await info.getWifiIPv6(); // 2001:0db8:85a3:0000:0000:8a2e:0370:7334
  var wifiSubmask = await info.getWifiSubmask(); // 255.255.255.0
  var wifiBroadcast = await info.getWifiBroadcast(); // 192.168.1.255
  var wifiGateway = await info.getWifiGatewayIP(); // 192.168.1.1
  print(wifiName);
  print(wifiBSSID);
  print(wifiIP);
  print(wifiIPv6);
  print(wifiSubmask);
  print(wifiBroadcast);
  print(wifiGateway);
  result['wifiName'] = wifiName ?? "";
  result['wifiBSSID'] = wifiBSSID ?? "";
  result['wifiIP'] = wifiIP ?? "";
  result['wifiIPv6'] = wifiIPv6 ?? "";
  result['wifiSubmask'] = wifiSubmask ?? "";
  result['wifiBroadcast'] = wifiBroadcast ?? "";
  result['wifiGateway'] = wifiGateway ?? "";
  return result;
}

class NetworkScanPage extends StatefulWidget {
  const NetworkScanPage({Key? key}) : super(key: key);

  @override
  _NetworkScanPageState createState() => _NetworkScanPageState();
}

class _NetworkScanPageState extends State<NetworkScanPage> {
  Set<DeviceModel> hosts = Set<DeviceModel>();
  LanScanner scanner = LanScanner();
  String subnet = "";

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getNetworkInfo().then((value) {
      subnet = ipToSubnet(value['wifiIP'] ?? "");
    });
  }

  StreamSubscription? _streamSubscription;
  bool _isListen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("sdf")),
      body: buildHostsListView(hosts),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          hosts.clear();
          if (_isListen) {
            _isListen = false;
            _streamSubscription?.cancel();
            return;
          }
          _isListen = true;
          var stream = scanner.preciseScan(
            // '192.168.0',
            "$subnet",
            progressCallback: (ProgressModel progress) {
              print('${progress.percent * 100}% $subnet.${progress.currIP}');
            },
          );

          _streamSubscription = stream.listen((DeviceModel device) {
            if (device.exists) {
              setState(() {
                hosts.add(device);
              });
            }
          });
        },
        tooltip: 'Start scanning',
        child: _isListen ? Icon(Icons.stop) : Icon(Icons.play_arrow),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  const StatusCard({
    Key? key,
    required this.text,
    required this.color,
  }) : super(key: key);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Text(
          text,
          style: TextStyle(color: Colors.white),
        ),
      ),
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }
}

Padding buildHostsListView(Set<DeviceModel> hosts) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: ListView.builder(
      shrinkWrap: true,
      itemCount: hosts.length,
      itemBuilder: (context, index) {
        DeviceModel currData = hosts.elementAt(index);

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: ListTile(
              leading: StatusCard(
                color: currData.exists ? Colors.greenAccent : Colors.redAccent,
                text: currData.exists ? "Online" : "Offline",
              ),
              title: Text(currData.ip ?? "N/A")),
        );
      },
    ),
  );
}
