import 'package:flutter/material.dart';
import 'package:obar/feature/home/home_screen.dart';

void main() {
  runApp(Obar());
}

class Obar extends StatelessWidget {
  const Obar({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false,home: HomeScreen());
  }
}
