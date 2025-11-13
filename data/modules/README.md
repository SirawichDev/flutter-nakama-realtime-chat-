# Nakama Image Upload Runtime Module (Go)

This module handles image upload to MinIO storage via Nakama RPC calls.

## Architecture

The module implements the following flow:
1. Client sends image data (base64) via RPC
2. Module uploads image to MinIO
3. Module returns image URL to client
4. Client sends message with image URL to chat channel
5. Other clients download image from URL

## RPC Functions

### `upload_image`
Uploads an image to MinIO storage.

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

The module is written in Go and compiled as a plugin for Nakama.

### Build

The Go module is automatically built when running `docker-compose up`:

```bash
docker-compose up --build
```

This will:
1. Compile the Go module into a plugin
2. Copy it into the Nakama container
3. Load it at runtime

### Manual Build

If you need to build manually:

```bash
cd go
go mod download
go build -trimpath -buildmode=plugin -o ../image_upload.so .
```

## Environment Variables

Set these in your `docker-compose.yml`:

- `MINIO_ENDPOINT`: MinIO server endpoint (default: `minio:9000`)
- `MINIO_ACCESS_KEY`: MinIO access key (default: `minioadmin`)
- `MINIO_SECRET_KEY`: MinIO secret key (default: `minioadmin`)
- `MINIO_USE_SSL`: Use SSL for MinIO connection (default: `false`)
- `MINIO_BUCKET`: Bucket name for chat images (default: `chat-images`)

## Files

- `go/main.go` - Main Go module source code
- `go/go.mod` - Go module dependencies
- `go/go.sum` - Go module checksums
