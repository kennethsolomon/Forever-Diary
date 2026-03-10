import { DynamoDBClient, BatchWriteItemCommand, QueryCommand } from "@aws-sdk/client-dynamodb";
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectsCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";

const dynamo = new DynamoDBClient({ region: "ap-southeast-1" });
const s3 = new S3Client({ region: "ap-southeast-1" });

const TABLE = "forever-diary";
const BUCKET = "forever-diary-photos-800759";
const MAX_ITEMS_PER_REQUEST = 100;

export const handler = async (event) => {
  const path = event.resource || event.path;
  const method = event.httpMethod;

  // Extract Cognito identity from request context
  const userId = event.requestContext?.identity?.cognitoIdentityId;
  if (!userId) {
    return respond(403, { error: "Unauthorized: no identity" });
  }

  try {
    if (path === "/sync" && method === "POST") {
      if (!event.body) {
        return respond(400, { error: "Request body required" });
      }
      return await handleSyncPush(userId, JSON.parse(event.body));
    }
    if (path === "/sync" && method === "GET") {
      return await handleSyncPull(userId, event.queryStringParameters);
    }
    if (path === "/presign" && method === "POST") {
      if (!event.body) {
        return respond(400, { error: "Request body required" });
      }
      return await handlePresign(userId, JSON.parse(event.body));
    }
    return respond(404, { error: "Not found" });
  } catch (err) {
    console.error("Handler error:", err);
    return respond(500, { error: "Internal server error" });
  }
};

// POST /sync — batch upsert or delete items in DynamoDB; optionally delete S3 objects
async function handleSyncPush(userId, body) {
  const { items, deleteS3Keys } = body;
  if (!items || !Array.isArray(items) || items.length === 0) {
    return respond(400, { error: "items array required" });
  }

  if (items.length > MAX_ITEMS_PER_REQUEST) {
    return respond(400, { error: `Maximum ${MAX_ITEMS_PER_REQUEST} items per request` });
  }

  // Limit batch size to 25 (DynamoDB limit)
  const batches = [];
  for (let i = 0; i < items.length; i += 25) {
    batches.push(items.slice(i, i + 25));
  }

  let written = 0;
  for (const batch of batches) {
    const requests = batch.map((item) => {
      if (item.operation === "delete") {
        return {
          DeleteRequest: {
            Key: marshall({ userId, sk: item.sk }),
          },
        };
      }
      // Strip reserved keys from item.data to prevent partition key overwrite
      const { userId: _, sk: __, ...safeData } = item.data || {};
      return {
        PutRequest: {
          Item: marshall({
            userId,
            sk: item.sk,
            ...safeData,
            updatedAt: item.updatedAt || new Date().toISOString(),
          }),
        },
      };
    });

    const result = await dynamo.send(
      new BatchWriteItemCommand({
        RequestItems: { [TABLE]: requests },
      })
    );

    // Retry unprocessed items with exponential backoff
    let unprocessed = result.UnprocessedItems?.[TABLE] || [];
    for (let attempt = 1; unprocessed.length > 0 && attempt <= 3; attempt++) {
      await new Promise((r) => setTimeout(r, 100 * Math.pow(2, attempt)));
      const retry = await dynamo.send(
        new BatchWriteItemCommand({
          RequestItems: { [TABLE]: unprocessed },
        })
      );
      unprocessed = retry.UnprocessedItems?.[TABLE] || [];
    }
    if (unprocessed.length > 0) {
      console.warn(`${unprocessed.length} items unprocessed after retries`);
    }

    written += batch.length - unprocessed.length;
  }

  // Delete S3 objects if requested
  if (Array.isArray(deleteS3Keys) && deleteS3Keys.length > 0) {
    // Scope keys to this user's prefix and batch into groups of 1000 (S3 limit)
    const s3Objects = deleteS3Keys.map((key) => ({
      Key: key.startsWith(`${userId}/`) ? key : `${userId}/${key}`,
    }));
    for (let i = 0; i < s3Objects.length; i += 1000) {
      const batch = s3Objects.slice(i, i + 1000);
      await s3.send(
        new DeleteObjectsCommand({
          Bucket: BUCKET,
          Delete: { Objects: batch, Quiet: true },
        })
      );
    }
  }

  return respond(200, { written });
}

// GET /sync — query items for user, optionally since a timestamp
async function handleSyncPull(userId, params) {
  const since = params?.since;
  let allItems = [];
  let lastKey = undefined;

  do {
    const queryParams = {
      TableName: TABLE,
      KeyConditionExpression: "userId = :uid",
      ExpressionAttributeValues: marshall({ ":uid": userId }),
      ExclusiveStartKey: lastKey,
    };

    if (since) {
      queryParams.FilterExpression = "updatedAt > :since";
      queryParams.ExpressionAttributeValues = marshall({
        ":uid": userId,
        ":since": since,
      });
    }

    const result = await dynamo.send(new QueryCommand(queryParams));
    const items = (result.Items || []).map((item) => unmarshall(item));
    allItems = allItems.concat(items);
    lastKey = result.LastEvaluatedKey;
  } while (lastKey);

  return respond(200, { items: allItems, count: allItems.length });
}

// POST /presign — generate S3 presigned URL for upload or download
async function handlePresign(userId, body) {
  const { key, operation } = body;
  if (!key || !operation) {
    return respond(400, { error: "key and operation required" });
  }
  if (operation !== "upload" && operation !== "download") {
    return respond(400, { error: "operation must be upload or download" });
  }

  // Ensure user can only access their own prefix
  const fullKey = `${userId}/${key}`;

  let command;
  if (operation === "upload") {
    command = new PutObjectCommand({
      Bucket: BUCKET,
      Key: fullKey,
      ContentType: "image/jpeg",
    });
  } else {
    command = new GetObjectCommand({
      Bucket: BUCKET,
      Key: fullKey,
    });
  }

  const url = await getSignedUrl(s3, command, { expiresIn: 900 }); // 15 min
  return respond(200, { url, key: fullKey });
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  };
}
