# Nakama Image Upload Runtime Module

This module handles image upload to Minio storage via Nakama RPC calls.

## Architecture

The module implements the following flow:
1. Client sends image data (base64) via RPC
2. Module uploads image to Minio
3. Module returns image URL to client
4. Client sends message with image URL to chat channel
5. Other clients download image from URL

## RPC Functions

### `upload_image`
Uploads an image to Minio storage.

**Request:**
```json
{
  "imageData": "base64_encoded_image",
  "contentType": "image/jpeg",
  "fileName": "example.jpg"
}
```

**Response:**
```json
{
  "success": true,
  "imageUrl": "http://minio:9000/...",
  "objectKey": "userId/timestamp_filename"
}
```

### `get_image_url`
Gets a presigned URL for an existing image.

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
  "imageUrl": "http://minio:9000/...",
  "objectKey": "userId/timestamp_filename"
}
```

## Development

1. Install dependencies:
```bash
npm install
```

2. Build:
```bash
npm run build
```

The built JavaScript will be in `build/main.js`.

## Environment Variables

- `MINIO_ENDPOINT`: Minio server endpoint (default: `minio:9000`)
- `MINIO_ACCESS_KEY`: Minio access key (default: `minioadmin`)
- `MINIO_SECRET_KEY`: Minio secret key (default: `minioadmin`)
- `MINIO_USE_SSL`: Use SSL for Minio connection (default: `false`)
- `MINIO_BUCKET`: Bucket name for chat images (default: `chat-images`)





