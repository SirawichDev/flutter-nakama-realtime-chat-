# Setup Guide - Flutter Nakama Image Chat

คู่มือการติดตั้งและรันระบบ Chat ที่รองรับการส่งรูปภาพผ่าน Minio

## สถาปัตยกรรมระบบ

```
Flutter Client → Nakama (WebSocket/RPC) → Minio Storage
     ↓                    ↓
  Display Image    Runtime Module
                   (TypeScript)
```

## Flow การส่งรูปภาพ

1. **Client 1** เลือกรูปและเรียก RPC `upload_image`
2. **Nakama Runtime** รับรูป (base64) และอัปโหลดไป **Minio**
3. **Minio** คืน URL ของรูปกลับมา
4. **Nakama** ส่ง URL ผ่าน WebSocket ไปหา **Client 2**
5. **Client 2** ดาวน์โหลดรูปจาก URL และแสดงผล

## ข้อกำหนดเบื้องต้น

- Docker & Docker Compose
- Flutter SDK (3.x+)
- Dart SDK
- Android Studio หรือ Xcode (สำหรับรันบน emulator/simulator)

## การติดตั้ง

### 1. รัน Docker Services

```bash
# สร้าง Docker images และรัน services
docker-compose up --build

# หรือรันใน background
docker-compose up --build -d
```

Services ที่จะรัน:
- **CockroachDB** (Database): Port 26257, 8080
- **Minio** (Object Storage): Port 9000 (API), 9001 (Console)
- **Nakama** (Game Server): Port 7350 (WebSocket), 7349 (HTTP)

### 2. เช็ค Services

```bash
# ดู logs
docker-compose logs -f

# เช็คสถานะ
docker-compose ps
```

**Minio Console:** http://localhost:9001
- Username: `minioadmin`
- Password: `minioadmin`

**Nakama Console:** http://localhost:7351
- Username: `admin`
- Password: `password`

### 3. รัน Flutter App

```bash
# ติดตั้ง dependencies
flutter pub get

# รันบน Android emulator
flutter run

# หรือรันบน iOS simulator
flutter run
```

## การใช้งาน

1. เปิดแอพบนอุปกรณ์หรือ emulator 2 เครื่อง
2. ใส่ username แตกต่างกันในแต่ละเครื่อง
3. เข้า chat room "general"
4. กดปุ่ม 📷 เพื่อเลือกรูปและส่ง
5. รูปจะปรากฏในทั้ง 2 เครื่อง

## Troubleshooting

### Android Emulator ไม่เชื่อมต่อ Nakama

แก้ไข `lib/services/nakama_service.dart` line 25-33:
```dart
String get host {
  if (Platform.isAndroid) {
    return '10.0.2.2'; // Android emulator special IP
  }
  // ...
}
```

### Minio Bucket ไม่ถูกสร้าง

Nakama Runtime Module จะสร้าง bucket อัตโนมัติเมื่อมีการอัปโหลดครั้งแรก
หรือสร้างด้วยตัวเองผ่าน Minio Console:

1. เข้า http://localhost:9001
2. Login ด้วย minioadmin/minioadmin
3. สร้าง bucket ชื่อ `chat-images`

### Image ไม่แสดงผล

ตรวจสอบ:
1. ไฟล์รูปมีขนาดไม่เกิน 5MB
2. เช็ค logs ใน console: `docker-compose logs -f nakama`
3. ตรวจสอบว่า Minio รันอยู่: `docker-compose ps`

## การหยุด Services

```bash
# หยุด services
docker-compose down

# หยุดและลบ volumes (ข้อมูลจะหายหมด)
docker-compose down -v
```

## โครงสร้างโปรเจค

```
.
├── data/
│   └── modules/          # Nakama Runtime Module (TypeScript)
│       ├── src/
│       │   └── main.ts   # RPC handlers
│       ├── package.json
│       └── tsconfig.json
├── lib/
│   ├── models/
│   │   └── chat_message.dart
│   ├── screens/
│   │   ├── chat_screen.dart
│   │   └── private_chat_screen.dart
│   └── services/
│       └── nakama_service.dart
├── docker-compose.yml    # Docker services configuration
├── Dockerfile           # Nakama container with runtime module
└── local.yml           # Nakama configuration
```

## API Reference

### Nakama RPC Functions

#### `upload_image`
อัปโหลดรูปภาพไป Minio

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
  "imageUrl": "http://localhost:9000/chat-images/...",
  "objectKey": "userId/timestamp_filename"
}
```

#### `get_image_url`
ขอ URL ของรูปที่อัปโหลดแล้ว

**Request:**
```json
{
  "objectKey": "userId/timestamp_filename"
}
```

**Response:**
```json
{
  "success": true,
  "imageUrl": "http://localhost:9000/chat-images/...",
  "objectKey": "userId/timestamp_filename"
}
```

## License

MIT





