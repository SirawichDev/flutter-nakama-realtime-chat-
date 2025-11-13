package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	nkruntime "github.com/heroiclabs/nakama-common/runtime"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const BUCKET_NAME = "chat-images"

var minioClient *minio.Client

// ImageUploadRequest represents the request payload for image upload
type ImageUploadRequest struct {
	ImageData   string `json:"imageData"`
	ContentType string `json:"contentType"`
	FileName    string `json:"fileName"`
}

// ImageUploadResponse represents the response for image upload
type ImageUploadResponse struct {
	Success   bool   `json:"success"`
	ImageURL  string `json:"imageUrl,omitempty"`
	ObjectKey string `json:"objectKey,omitempty"`
	Error     string `json:"error,omitempty"`
}

// InitializeMinioClient initializes the Minio client
func InitializeMinioClient(logger nkruntime.Logger) error {
	endpoint := os.Getenv("MINIO_ENDPOINT")
	if endpoint == "" {
		endpoint = "minio:9000"
	}

	accessKey := os.Getenv("MINIO_ACCESS_KEY")
	if accessKey == "" {
		accessKey = "minioadmin"
	}

	secretKey := os.Getenv("MINIO_SECRET_KEY")
	if secretKey == "" {
		secretKey = "minioadmin"
	}

	useSSL := os.Getenv("MINIO_USE_SSL") == "true"

	logger.Info("Initializing Minio client with endpoint: %s", endpoint)

	// Parse endpoint
	endpointParts := strings.Split(endpoint, ":")
	endPoint := endpointParts[0]
	port := 9000
	if len(endpointParts) > 1 {
		if p, err := strconv.Atoi(endpointParts[1]); err == nil {
			port = p
		}
	}

	// Initialize Minio client
	var err error
	endpointURL := fmt.Sprintf("%s:%d", endPoint, port)
	minioClient, err = minio.New(endpointURL, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
		Region: "us-east-1",
	})
	if err != nil {
		return fmt.Errorf("failed to create Minio client: %v", err)
	}

	logger.Info("Minio client initialized successfully")
	return nil
}

// EnsureBucketExists ensures the bucket exists, creates it if it doesn't
func EnsureBucketExists(ctx context.Context, logger nkruntime.Logger) error {
	exists, err := minioClient.BucketExists(ctx, BUCKET_NAME)
	if err != nil {
		return fmt.Errorf("failed to check bucket existence: %v", err)
	}

	if !exists {
		logger.Info("Bucket %s does not exist, creating...", BUCKET_NAME)
		err = minioClient.MakeBucket(ctx, BUCKET_NAME, minio.MakeBucketOptions{Region: "us-east-1"})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %v", err)
		}
		logger.Info("Bucket %s created successfully", BUCKET_NAME)

		// Set bucket policy to allow public read
		policy := `{
			"Version": "2012-10-17",
			"Statement": [
				{
					"Effect": "Allow",
					"Principal": {"AWS": ["*"]},
					"Action": ["s3:GetObject"],
					"Resource": ["arn:aws:s3:::` + BUCKET_NAME + `/*"]
				}
			]
		}`
		err = minioClient.SetBucketPolicy(ctx, BUCKET_NAME, policy)
		if err != nil {
			logger.Warn("Failed to set bucket policy: %v", err)
		} else {
			logger.Info("Bucket policy set for %s", BUCKET_NAME)
		}
	}

	return nil
}

// RpcUploadImage handles image upload via RPC
func RpcUploadImage(ctx context.Context, logger nkruntime.Logger, db *sql.DB, nk nkruntime.NakamaModule, payload string) (string, error) {
	logger.Info("Received image upload request")

	// Parse request payload
	var request ImageUploadRequest
	if err := json.Unmarshal([]byte(payload), &request); err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to parse request: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	if request.ImageData == "" || request.ContentType == "" || request.FileName == "" {
		response := ImageUploadResponse{
			Success: false,
			Error:   "Missing required fields: imageData, contentType, or fileName",
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	logger.Info("Processing image upload: %s, type: %s", request.FileName, request.ContentType)

	// Initialize Minio client if not already initialized
	if minioClient == nil {
		if err := InitializeMinioClient(logger); err != nil {
			response := ImageUploadResponse{
				Success: false,
				Error:   fmt.Sprintf("Failed to initialize Minio client: %v", err),
			}
			responseJSON, _ := json.Marshal(response)
			return string(responseJSON), nil
		}
	}

	// Ensure bucket exists
	if err := EnsureBucketExists(ctx, logger); err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to ensure bucket exists: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	// Generate unique object key
	timestamp := time.Now().UnixMilli()
	// Get user ID from context (Nakama sets user_id in context)
	userId := "anonymous"
	if uid := ctx.Value("user_id"); uid != nil {
		if uidStr, ok := uid.(string); ok {
			userId = uidStr
		}
	}
	objectKey := fmt.Sprintf("%s/%d_%s", userId, timestamp, request.FileName)

	logger.Info("Uploading image with object key: %s", objectKey)

	// Decode base64 image data
	imageData, err := base64.StdEncoding.DecodeString(request.ImageData)
	if err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to decode base64 image: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	imageSize := int64(len(imageData))
	logger.Info("Image size: %d bytes", imageSize)

	// Upload to Minio
	_, err = minioClient.PutObject(ctx, BUCKET_NAME, objectKey, bytes.NewReader(imageData), imageSize, minio.PutObjectOptions{
		ContentType: request.ContentType,
	})
	if err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to upload image: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	logger.Info("Image uploaded successfully: %s", objectKey)

	// Generate presigned URL (expires in 7 days)
	imageURL, err := minioClient.PresignedGetObject(ctx, BUCKET_NAME, objectKey, 7*24*time.Hour, nil)
	if err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to generate presigned URL: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	logger.Info("Generated image URL: %s", imageURL.String())

	response := ImageUploadResponse{
		Success:   true,
		ImageURL:  imageURL.String(),
		ObjectKey: objectKey,
	}

	responseJSON, _ := json.Marshal(response)
	return string(responseJSON), nil
}

// RpcGetImageUrl gets presigned URL for existing image
func RpcGetImageUrl(ctx context.Context, logger nkruntime.Logger, db *sql.DB, nk nkruntime.NakamaModule, payload string) (string, error) {
	logger.Info("Received get image URL request")

	// Parse request payload
	var request struct {
		ObjectKey string `json:"objectKey"`
	}
	if err := json.Unmarshal([]byte(payload), &request); err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to parse request: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	if request.ObjectKey == "" {
		response := ImageUploadResponse{
			Success: false,
			Error:   "Missing required field: objectKey",
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	// Initialize Minio client if not already initialized
	if minioClient == nil {
		if err := InitializeMinioClient(logger); err != nil {
			response := ImageUploadResponse{
				Success: false,
				Error:   fmt.Sprintf("Failed to initialize Minio client: %v", err),
			}
			responseJSON, _ := json.Marshal(response)
			return string(responseJSON), nil
		}
	}

	// Generate presigned URL (expires in 7 days)
	imageURL, err := minioClient.PresignedGetObject(ctx, BUCKET_NAME, request.ObjectKey, 7*24*time.Hour, nil)
	if err != nil {
		response := ImageUploadResponse{
			Success: false,
			Error:   fmt.Sprintf("Failed to generate presigned URL: %v", err),
		}
		responseJSON, _ := json.Marshal(response)
		return string(responseJSON), nil
	}

	response := ImageUploadResponse{
		Success:   true,
		ImageURL:  imageURL.String(),
		ObjectKey: request.ObjectKey,
	}

	responseJSON, _ := json.Marshal(response)
	return string(responseJSON), nil
}

// InitModule initializes the module
func InitModule(ctx context.Context, logger nkruntime.Logger, db *sql.DB, nk nkruntime.NakamaModule, initializer nkruntime.Initializer) error {
	logger.Info("Image Upload Module loaded")

	// Register RPC functions
	if err := initializer.RegisterRpc("upload_image", RpcUploadImage); err != nil {
		return fmt.Errorf("failed to register upload_image RPC: %v", err)
	}

	if err := initializer.RegisterRpc("get_image_url", RpcGetImageUrl); err != nil {
		return fmt.Errorf("failed to register get_image_url RPC: %v", err)
	}

	logger.Info("RPC functions registered: upload_image, get_image_url")
	return nil
}
