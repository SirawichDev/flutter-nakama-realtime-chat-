// Nakama Runtime Module for Image Upload with Minio
// This module handles the image upload flow:
// 1. Client sends image data via RPC
// 2. Request presigned URL from Minio
// 3. Upload image to Minio using presigned URL
// 4. Return image URL to client

import * as Minio from 'minio';

interface ImageUploadRequest {
  imageData: string; // base64 encoded image
  contentType: string; // e.g., "image/jpeg", "image/png"
  fileName: string;
}

interface ImageUploadResponse {
  success: boolean;
  imageUrl?: string;
  objectKey?: string;
  error?: string;
}

let minioClient: Minio.Client;
const BUCKET_NAME = 'chat-images';

/**
 * Initialize Minio client
 */
function initializeMinioClient(ctx: nkruntime.Context, logger: nkruntime.Logger): void {
  const endpoint = ctx.env['MINIO_ENDPOINT'] || 'minio:9000';
  const accessKey = ctx.env['MINIO_ACCESS_KEY'] || 'minioadmin';
  const secretKey = ctx.env['MINIO_SECRET_KEY'] || 'minioadmin';
  const useSSL = ctx.env['MINIO_USE_SSL'] === 'true';

  logger.info(`Initializing Minio client with endpoint: ${endpoint}`);

  minioClient = new Minio.Client({
    endPoint: endpoint.split(':')[0],
    port: parseInt(endpoint.split(':')[1]) || 9000,
    useSSL: useSSL,
    accessKey: accessKey,
    secretKey: secretKey,
  });

  logger.info('Minio client initialized successfully');
}

/**
 * Ensure bucket exists, create if it doesn't
 */
async function ensureBucketExists(logger: nkruntime.Logger): Promise<void> {
  try {
    const exists = await minioClient.bucketExists(BUCKET_NAME);
    if (!exists) {
      logger.info(`Bucket ${BUCKET_NAME} does not exist, creating...`);
      await minioClient.makeBucket(BUCKET_NAME, 'us-east-1');
      logger.info(`Bucket ${BUCKET_NAME} created successfully`);
      
      // Set bucket policy to allow public read
      const policy = {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: { AWS: ['*'] },
            Action: ['s3:GetObject'],
            Resource: [`arn:aws:s3:::${BUCKET_NAME}/*`],
          },
        ],
      };
      await minioClient.setBucketPolicy(BUCKET_NAME, JSON.stringify(policy));
      logger.info(`Bucket policy set for ${BUCKET_NAME}`);
    }
  } catch (error) {
    logger.error(`Error ensuring bucket exists: ${error}`);
    throw error;
  }
}

/**
 * RPC function to handle image upload
 */
async function rpcUploadImage(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): Promise<string> {
  logger.info('Received image upload request');

  try {
    // Parse request payload
    const request: ImageUploadRequest = JSON.parse(payload);
    
    if (!request.imageData || !request.contentType || !request.fileName) {
      throw new Error('Missing required fields: imageData, contentType, or fileName');
    }

    logger.info(`Processing image upload: ${request.fileName}, type: ${request.contentType}`);

    // Initialize Minio client if not already initialized
    if (!minioClient) {
      initializeMinioClient(ctx, logger);
    }

    // Ensure bucket exists
    await ensureBucketExists(logger);

    // Generate unique object key
    const timestamp = Date.now();
    const userId = ctx.userId;
    const objectKey = `${userId}/${timestamp}_${request.fileName}`;

    logger.info(`Uploading image with object key: ${objectKey}`);

    // Decode base64 image data
    const imageBuffer = Buffer.from(request.imageData, 'base64');
    const imageSize = imageBuffer.length;

    logger.info(`Image size: ${imageSize} bytes`);

    // Upload to Minio
    await minioClient.putObject(
      BUCKET_NAME,
      objectKey,
      imageBuffer,
      imageSize,
      {
        'Content-Type': request.contentType,
      }
    );

    logger.info(`Image uploaded successfully: ${objectKey}`);

    // Generate public URL for the image
    // For development, we use presigned URL that expires in 7 days
    const imageUrl = await minioClient.presignedGetObject(
      BUCKET_NAME,
      objectKey,
      7 * 24 * 60 * 60 // 7 days
    );

    logger.info(`Generated image URL: ${imageUrl}`);

    const response: ImageUploadResponse = {
      success: true,
      imageUrl: imageUrl,
      objectKey: objectKey,
    };

    return JSON.stringify(response);
  } catch (error) {
    logger.error(`Image upload error: ${error}`);
    
    const response: ImageUploadResponse = {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };

    return JSON.stringify(response);
  }
}

/**
 * RPC function to get presigned URL for existing image
 */
async function rpcGetImageUrl(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): Promise<string> {
  logger.info('Received get image URL request');

  try {
    const request = JSON.parse(payload);
    
    if (!request.objectKey) {
      throw new Error('Missing required field: objectKey');
    }

    // Initialize Minio client if not already initialized
    if (!minioClient) {
      initializeMinioClient(ctx, logger);
    }

    // Generate presigned URL (expires in 7 days)
    const imageUrl = await minioClient.presignedGetObject(
      BUCKET_NAME,
      request.objectKey,
      7 * 24 * 60 * 60 // 7 days
    );

    const response: ImageUploadResponse = {
      success: true,
      imageUrl: imageUrl,
      objectKey: request.objectKey,
    };

    return JSON.stringify(response);
  } catch (error) {
    logger.error(`Get image URL error: ${error}`);
    
    const response: ImageUploadResponse = {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };

    return JSON.stringify(response);
  }
}

/**
 * Initialize function - called when the runtime module is loaded
 */
function InitModule(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  logger.info('Image Upload Module loaded');

  // Register RPC functions
  initializer.registerRpc('upload_image', rpcUploadImage);
  initializer.registerRpc('get_image_url', rpcGetImageUrl);

  logger.info('RPC functions registered: upload_image, get_image_url');
}

// Required for Nakama to load the module
// @ts-ignore
!InitModule && InitModule.bind(null);





