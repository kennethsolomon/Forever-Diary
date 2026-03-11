import { DynamoDBClient, BatchWriteItemCommand, QueryCommand, UpdateItemCommand } from "@aws-sdk/client-dynamodb";
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

// POST /sync — upsert items with LWW or delete items; optionally delete S3 objects
async function handleSyncPush(userId, body) {
  const { items, deleteS3Keys } = body;
  if (!items || !Array.isArray(items) || items.length === 0) {
    return respond(400, { error: "items array required" });
  }

  if (items.length > MAX_ITEMS_PER_REQUEST) {
    return respond(400, { error: `Maximum ${MAX_ITEMS_PER_REQUEST} items per request` });
  }

  const puts = items.filter((i) => i.operation !== "delete");
  const deletes = items.filter((i) => i.operation === "delete");

  // Upsert with last-write-wins: only accept if incoming updatedAt >= stored updatedAt
  let written = 0;
  let skipped = 0;
  for (const item of puts) {
    const { userId: _, sk: __, ...safeData } = item.data || {};
    const newUpdatedAt = item.updatedAt || new Date().toISOString();

    const { updateExpression, conditionExpression, expressionAttributeNames, expressionAttributeValues } =
      buildUpdateParams(safeData, newUpdatedAt);

    try {
      await dynamo.send(
        new UpdateItemCommand({
          TableName: TABLE,
          Key: marshall({ userId, sk: item.sk }),
          UpdateExpression: updateExpression,
          ConditionExpression: conditionExpression,
          ExpressionAttributeNames: expressionAttributeNames,
          ExpressionAttributeValues: expressionAttributeValues,
        })
      );
      written++;
    } catch (err) {
      if (err.name === "ConditionalCheckFailedException") {
        // Server already has a newer version — skip silently; client will reconcile on next pull
        skipped++;
      } else {
        throw err;
      }
    }
  }

  // Hard-delete items (child records, tombstones already pushed as updates above)
  let deleted = 0;
  if (deletes.length > 0) {
    const batches = [];
    for (let i = 0; i < deletes.length; i += 25) {
      batches.push(deletes.slice(i, i + 25));
    }

    for (const batch of batches) {
      const requests = batch.map((item) => ({
        DeleteRequest: {
          Key: marshall({ userId, sk: item.sk }),
        },
      }));

      const result = await dynamo.send(
        new BatchWriteItemCommand({ RequestItems: { [TABLE]: requests } })
      );

      // Retry unprocessed items with exponential backoff
      let unprocessed = result.UnprocessedItems?.[TABLE] || [];
      for (let attempt = 1; unprocessed.length > 0 && attempt <= 3; attempt++) {
        await new Promise((r) => setTimeout(r, 100 * Math.pow(2, attempt)));
        const retry = await dynamo.send(
          new BatchWriteItemCommand({ RequestItems: { [TABLE]: unprocessed } })
        );
        unprocessed = retry.UnprocessedItems?.[TABLE] || [];
      }
      if (unprocessed.length > 0) {
        console.warn(`${unprocessed.length} delete items unprocessed after retries`);
      }
      deleted += batch.length;
    }
  }

  // Delete S3 objects if requested
  if (Array.isArray(deleteS3Keys) && deleteS3Keys.length > 0) {
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

  const serverTime = new Date().toISOString();
  return respond(200, { written, skipped, deleted, serverTime });
}

// GET /sync — query items for user, optionally since a timestamp; returns server-side timestamp
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

  const serverTime = new Date().toISOString();
  return respond(200, { items: allItems, count: allItems.length, serverTime });
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

// Build UpdateItem expression parts for LWW conditional write.
// All attribute names are aliased with #f_ prefix to avoid DynamoDB reserved words.
function buildUpdateParams(data, updatedAt) {
  const setExpressions = [];
  const removeExpressions = [];
  const attrNames = {};
  const attrValues = {};

  for (const [key, value] of Object.entries(data)) {
    const nameAlias = `#f_${key}`;
    const valueAlias = `:v_${key}`;
    attrNames[nameAlias] = key;
    attrValues[valueAlias] = value;
    setExpressions.push(`${nameAlias} = ${valueAlias}`);
  }

  // updatedAt tracked separately for the condition
  attrNames["#updatedAt"] = "updatedAt";
  attrValues[":newUpdatedAt"] = updatedAt;
  setExpressions.push("#updatedAt = :newUpdatedAt");

  // Remove stale tombstone marker when this is a live (non-deleted) update.
  // UpdateItem only sets attributes — without this, a prior deletedAt persists
  // in DynamoDB and causes all subsequent pulls to re-delete the entry.
  if (!("deletedAt" in data)) {
    attrNames["#deletedAt"] = "deletedAt";
    removeExpressions.push("#deletedAt");
  }

  let updateExpression = `SET ${setExpressions.join(", ")}`;
  if (removeExpressions.length > 0) {
    updateExpression += ` REMOVE ${removeExpressions.join(", ")}`;
  }

  return {
    updateExpression,
    // Write only if no record exists yet, or the incoming update is newer/equal
    conditionExpression:
      "attribute_not_exists(#updatedAt) OR #updatedAt <= :newUpdatedAt",
    expressionAttributeNames: attrNames,
    expressionAttributeValues: marshall(attrValues),
  };
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
