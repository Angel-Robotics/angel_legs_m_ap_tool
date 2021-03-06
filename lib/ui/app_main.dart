import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'tool_home_page.dart';

class AppMain extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '엔젤렉스M 통신모듈 툴',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ToolHomePage(title: '엔젤렉스M 통신모듈 툴'),
    );
  }
}
