import 'package:flutter/material.dart';

class AppConstants {
  // --- CONFIGURAZIONE BLUETOOTH BLE ---
  
  // --- CHIAVE DI MEMORIA LOCALE ---
  static const String prefMacAddressKey = "saved_esp32_mac";

  // UUID del firmware
  static const String serviceUuid = "fc96f65e-318a-4001-84bd-77e9d12af44b";
  static const String characteristicUuidRx = "94b43599-5ea2-41e7-9d99-6ff9b904ae3a";
  static const String characteristicUuidTx = "04d3552e-b9b3-4be6-a8b4-aa43c4507c4d";

  // --- RETE E WEBVIEW ---
  static const String defaultIpAddress = "192.168.4.1";
  static const String webConfigPath = "/config";

  // --- TEMPORIZZAZIONE ---
  static const int cmdTransmissionIntervalMs = 120;
  static const int bleReconnectTimeoutSeconds = 5;
  static const int bleScanDurationSeconds = 10;

  static const String keepAliveAckCommand = "#ACK";

  static const int keepAliveAckDataKey = 0x02E5;

  // --- DIMENSIONI JOYSTICK PICCOLI (TILT / LIFT) ---
  static const double smallJoystickSize = 145.0;
  static const double smallJoystickThumbSize = 60.0;

  // --- DIMENSIONI JOYSTICK GRANDI (STEER / SPEED) ---
  static const double largeJoystickSize = 180.0;
  static const double largeJoystickThumbSize = 80.0;

  // --- POSIZIONAMENTO JOYSTICK ---
  static const double smallJoystickHorizontalPadding = 10.0;
  static const double largeJoystickHorizontalPadding = 72.0;
  static const double smallJoystickTopPadding = 20.0;
  static const double largeJoystickBottomPadding = 20.0;

  // --- INTERFACCIA E PULSANTI ---
  static const double centerButtonIconSize = 55.0;
  static const double batteryWidth = 55.0;
  static const double batteryHeight = 18.0;

  // --- STILE E COLORI ---
  static const Color backgroundColor = Color(0xFFF0F2F5);
  static const Color dashboardBackgroundColor = Color(0xFFE9EBEF);
  static const Color smallJoystickColor = Colors.green;
  static const Color largeJoystickColor = Colors.amber;
  static const Color centerButtonColor = Colors.blue;
  static const Color centerButtonActiveColor = Colors.amber;
}
