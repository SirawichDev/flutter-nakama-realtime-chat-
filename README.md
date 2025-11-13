# Flutter Nakama Chat with Image Support

Real-time direct messaging (DM) application built with Flutter and Nakama, supporting text messages and image sharing via MinIO storage.

## ✨ Features

- ✅ **Real-time Direct Messaging** - 1-on-1 private chat with other users
- ✅ **User Presence** - See who's online in real-time
- ✅ **Text Messaging** - Send and receive text messages instantly
- ✅ **Image Sharing** - Pick images from gallery and share via chat
- ✅ **Local Message Storage** - Offline message history using SharedPreferences
- ✅ **Server-side Message History** - Fetch message history from Nakama server
- ✅ **Pagination** - Load more messages as you scroll
- ✅ **Image Storage** - Images stored in MinIO with presigned URLs

## 🏗️ Architecture

```
┌─────────────────┐
│  Flutter Client │
└────────┬────────┘
         │ WebSocket/RPC
         ▼
┌─────────────────┐      ┌──────────────┐
│  Nakama Server  │─────▶│    MinIO     │
│  (Go Modules)   │      │ (Images)     │
└────────┬────────┘      └──────────────┘
         │
         ▼
┌─────────────────┐
│  CockroachDB    │
│  (Messages)     │
└─────────────────┘
```

## 📱 App Flow

### 1. Authentication & User List

```
┌────────────┐
│   Start    │
└─────┬──────┘
      │
      ▼
┌────────────────────┐
│ Enter Username     │ ← Username Dialog
└─────┬──────────────┘
      │
      ▼
┌────────────────────┐
│ Authenticate with  │
│ Nakama (Device ID) │
└─────┬──────────────┘
      │
      ▼
┌────────────────────┐
│ Join "general"     │ ← Discover other users
│ channel            │
└─────┬──────────────┘
      │
      ▼
┌────────────────────┐
│ User List Screen   │ ← Show online users
│ - See all users    │
│ - User presence    │
│ - Select to chat   │
└─────┬──────────────┘
      │
      │ (Tap user)
      ▼
```

### 2. Direct Message Chat

```
┌────────────────────┐
│ Private Chat       │
│ Screen             │
└─────┬──────────────┘
      │
      ├──▶ Load message history from server
      │    └─ If fails → Load from local storage
      │
      ├──▶ Listen for new messages (WebSocket)
      │    └─ Save to local storage
      │
      └──▶ Send messages:
           ├─ Text: sendTextMessage()
           └─ Image: sendImageMessage()
                └─ Upload to MinIO via RPC
                └─ Send message with image URL
```

### 3. Image Flow

```
Pick Image → Upload to MinIO → Get URL → Send Message
                    │                         │
                    ▼                         ▼
              [Base64 encode]          [Image URL in
                    │                   message content]
                    ▼                         │
              [RPC: upload_image]             ▼
                    │                   Other users
                    ▼                   receive message
              [MinIO storage]                 │
                    │                         ▼
                    └──────[Presigned URL]──▶ Download &
                                               Display
```

## 🚀 Quick Start

### Prerequisites

- **Docker** and **Docker Compose**
- **Flutter SDK** (>=3.0.0)
- **Android Studio** or **Xcode** (for emulator/simulator)

### 1. Start Backend Services

```bash
# Start all services (CockroachDB, MinIO, Nakama)
docker-compose up --build

# Or run in background
docker-compose up --build -d
```

**Services:**
- CockroachDB: Port 26257 (database), 8080 (admin UI)
- MinIO: Port 9000 (API), 9001 (console)
- Nakama: Port 7349 (gRPC), 7350 (HTTP/WebSocket), 7351 (console)

**Access consoles:**
- MinIO Console: http://localhost:9001 (minioadmin / minioadmin)
- Nakama Console: http://localhost:7351 (admin / password)

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Run the App

```bash
# Run on Android emulator
flutter run

# Run on iOS simulator
flutter run
```

## 🎮 Usage Guide

### Step-by-Step

1. **Launch the app** on 2 devices/emulators
2. **Enter different usernames** on each device
3. **Wait for user list** to populate (shows online users)
4. **Tap a user** to start a private chat
5. **Send messages:**
   - Type text and press send button
   - Tap 📷 icon to pick and send images
6. **Messages sync** in real-time between devices

### Features in Chat

- **Text Messages**: Type in the input field
- **Image Messages**: Tap image icon to pick from gallery
- **Scroll to Load**: Scroll up to load older messages
- **Message Status**: Messages show timestamp
- **User Identification**: Your messages appear on the right (blue), others on the left (gray)

## 📂 Project Structure

```
.
├── lib/
│   ├── main.dart                       # App entry point
│   ├── models/
│   │   └── chat_message.dart          # Message data model
│   ├── screens/
│   │   ├── user_list_screen.dart      # User list (home screen)
│   │   └── private_chat_screen.dart   # 1-on-1 chat screen
│   ├── services/
│   │   ├── nakama_service.dart        # Nakama client & methods
│   │   ├── nakama_constants.dart      # Configuration constants
│   │   ├── nakama_exceptions.dart     # Custom exceptions
│   │   └── chat_storage_service.dart  # Local storage
│   └── utils/
│       └── logger.dart                 # Logging utility
├── data/
│   ├── modules/
│   │   └── go/                         # Nakama Go runtime modules
│   │       ├── main.go                 # Image upload RPCs
│   │       ├── go.mod
│   │       └── go.sum
│   └── minio/                          # MinIO data (images)
├── docker-compose.yml                  # Docker services setup
├── Dockerfile                          # Nakama + Go modules
├── local.yml                           # Nakama config
└── README.md                           # This file
```

## 🔧 Configuration

### Nakama Connection

The app automatically detects the platform and uses the correct host:

- **Android Emulator**: `10.0.2.2` (maps to host machine)
- **iOS Simulator**: `127.0.0.1`
- **Other Platforms**: `127.0.0.1`

Configuration is in `lib/services/nakama_constants.dart`:

```dart
static const int httpPort = 7350;
static const int grpcPort = 7349;
static const String serverKey = 'defaultkey';
static const bool useSSL = false;
static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
```

## 📦 Dependencies

### Flutter

```yaml
dependencies:
  nakama: ^1.3.0                    # Nakama SDK
  image_picker: ^1.0.7              # Image selection
  http: ^1.1.2                      # HTTP client
  device_info_plus: ^10.1.0         # Device info
  shared_preferences: ^2.2.2        # Local storage
```

### Backend

- **Nakama 3.24.0** - Game server
- **CockroachDB** - Database
- **MinIO** - Object storage
- **Go 1.x** - Runtime modules

## 🔌 API Reference

### Nakama RPC Functions

#### `upload_image`
Upload an image to MinIO storage.

**Request:**
```json
{
  "imageData": "base64_encoded_image",
  "contentType": "image/jpeg",
  "fileName": "photo.jpg"
}
```

**Response:**
```json
{
  "success": true,
  "imageUrl": "http://minio:9000/chat-images/userId/timestamp_photo.jpg",
  "objectKey": "userId/timestamp_photo.jpg"
}
```

#### `get_image_url`
Get a presigned URL for an existing image.

**Request:**
```json
{
  "objectKey": "userId/timestamp_photo.jpg"
}
```

**Response:**
```json
{
  "success": true,
  "imageUrl": "http://minio:9000/chat-images/...",
  "objectKey": "userId/timestamp_photo.jpg"
}
```

## 🐛 Troubleshooting

### Android Emulator Can't Connect

The app automatically uses `10.0.2.2` for Android emulators. If connection fails:

1. Check Docker services are running: `docker-compose ps`
2. Check Nakama logs: `docker-compose logs -f nakama`
3. Verify ports are exposed: `7349`, `7350`, `7351`

### Images Not Displaying

1. **Check image size**: Must be under 5MB
2. **Check MinIO**: Visit http://localhost:9001
3. **Check bucket exists**: Bucket `chat-images` should be created automatically
4. **Check logs**: `docker-compose logs -f nakama`

### MinIO Bucket Not Created

The Go module creates the bucket automatically on first upload. To create manually:

1. Visit http://localhost:9001
2. Login: minioadmin / minioadmin
3. Create bucket: `chat-images`

### Connection Timeout

1. Ensure Docker services are healthy: `docker-compose ps`
2. Restart services: `docker-compose restart`
3. Check firewall settings
4. Try `docker-compose down && docker-compose up --build`

### Message History Not Loading

The app tries to load from server first, then falls back to local storage. If both fail:

1. Check Nakama connection
2. Clear local storage: Uninstall and reinstall app
3. Check console logs for errors

## 🛑 Stopping Services

```bash
# Stop services (keep data)
docker-compose down

# Stop and remove all data
docker-compose down -v
```

## 🔐 Security Notes

- **Authentication**: Uses device ID (unique per session)
- **Display Names**: Can be duplicated (not enforced as unique)
- **Image URLs**: Presigned URLs expire in 7 days
- **Production**: Change server keys and credentials in production

## 📝 Best Practices

### Code Organization

- Services use singleton pattern
- Custom exceptions for better error handling
- Logger utility for consistent logging
- Constants separated from code
- Models for type safety

### Performance

- Image compression (80% quality)
- Pagination for message history
- Local caching of messages
- Efficient image loading

## 🚢 Deployment

### Production Checklist

- [ ] Change Nakama server key
- [ ] Change MinIO credentials
- [ ] Update database password
- [ ] Enable SSL/TLS
- [ ] Configure proper CORS
- [ ] Set up monitoring
- [ ] Configure backups
- [ ] Update host configuration

## 📄 License

MIT

---

**Built with** ❤️ **using Flutter, Nakama, and MinIO**
