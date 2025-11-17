/// Represents the connection status of the USB scale
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error;

  bool get isConnected => this == ConnectionStatus.connected;
  bool get isDisconnected => this == ConnectionStatus.disconnected;
  bool get isConnecting => this == ConnectionStatus.connecting;
  bool get hasError => this == ConnectionStatus.error;

  String get displayText {
    switch (this) {
      case ConnectionStatus.disconnected:
        return 'USB Disconnected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.error:
        return 'Connection Error';
    }
  }
}
