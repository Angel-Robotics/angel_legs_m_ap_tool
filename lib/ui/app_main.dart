import 'package:flutter/material.dart';
import 'tool_home_page.dart';

class AppMain extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '엔젤렉스M 통신모듈 툴',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ToolHomePage(title: '엔젤렉스M 통신모듈 툴'),
    );
  }
}
