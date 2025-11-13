# Flutter Nakama Chat with Image Support

Flutter project that integrates with Nakama server for real-time chat functionality, supporting both text messages and image sharing.

## Features

- ✅ Real-time text messaging via Nakama chat channels
- ✅ Image sharing (pick from gallery and send)
- ✅ User authentication with Nakama
- ✅ Chat channel management
- ✅ Image storage and retrieval from Nakama storage

## Prerequisites

1. **Flutter SDK**: Make sure you have Flutter installed (SDK >=3.0.0)
2. **Nakama Server**: You need a running Nakama server instance

### Running Nakama Server

You can run Nakama server using Docker or Podman:

**Using Docker:**
```bash
docker run -p 7349:7349 -p 7350:7350 -p 7351:7351 heroiclabs/nakama:3.24.0
```

**Using Podman:**
```bash
# 1. เริ่ม podman machine (ถ้ายังไม่ได้ start)
podman machine start

# 2. สร้าง network
podman network create nakama-network

# 3. รัน CockroachDB
podman run -d --name nakama-db --network nakama-network \
  -p 26257:26257 -p 8080:8080 \
  cockroachdb/cockroach:latest start-single-node --insecure

# 4. สร้าง database
podman exec nakama-db cockroach sql --insecure -e "CREATE DATABASE IF NOT EXISTS nakama;"

# 5. รัน Nakama (ต้องใช้ config file หรือ environment variables)
# ดูตัวอย่างใน docker-compose.yml สำหรับการตั้งค่า
```

**หมายเหตุ:** Podman ต้องการการตั้งค่าที่ซับซ้อนกว่า Docker สำหรับ Nakama แนะนำให้ใช้ Docker หรือ docker-compose สำหรับการ development

Or download from: https://github.com/heroiclabs/nakama/releases

## Configuration

Edit `lib/services/nakama_service.dart` to configure your Nakama server:

```dart
final String host = '127.0.0.1';  // Change to your Nakama server IP
final int port = 7350;
final String serverKey = 'defaultkey';  // Change if using custom server key
final bool ssl = false;  // Set to true if using HTTPS
```

## Installation

1. Install dependencies:
```bash
flutter pub get
```

2. Run the app:
```bash
flutter run
```

## Usage

1. When the app starts, enter your username to connect
2. You'll be automatically joined to the "general" chat channel
3. Type messages in the text field and press send
4. Tap the image icon to pick and send images from your gallery

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── chat_message.dart    # Chat message model
├── screens/
│   └── chat_screen.dart     # Main chat UI
└── services/
    └── nakama_service.dart  # Nakama SDK integration
```

## Dependencies

- `nakama`: Nakama SDK for Flutter
- `image_picker`: For selecting images from device
- `http`: HTTP client for network operations

## Notes

- Images are stored in Nakama storage and sent as references in chat messages
- The app uses device authentication (you can modify to use email/password)
- Default channel name is "general" (can be changed in `chat_screen.dart`)

