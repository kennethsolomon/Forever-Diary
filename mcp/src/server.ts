import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";
import { unmarshall } from "@aws-sdk/util-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";

// ---- Config ----------------------------------------------------------------

const TABLE = process.env.DYNAMODB_TABLE ?? "forever-diary";
const REGION = process.env.AWS_REGION ?? "ap-southeast-1";
const BUCKET = process.env.S3_BUCKET ?? "forever-diary-photos-800759";

// ---- DynamoDB client -------------------------------------------------------

function makeDynamoClient() {
  return new DynamoDBClient({ region: REGION });
}

// ---- Helpers ---------------------------------------------------------------

interface CheckIn {
  templateId: string;
  label: string;
  type: string;
  boolValue?: boolean;
  textValue?: string;
  numberValue?: number;
}

interface DiaryEntry {
  date: string;
  year: number;
  monthDayKey: string;
  weekday: string;
  text: string;
  location: string | null;
  updatedAt: string;
  checkIns: CheckIn[];
  photoCount: number;
}

function formatEntry(item: Record<string, unknown>): DiaryEntry {
  return {
    date: (item.date as string) ?? "",
    year: (item.year as number) ?? 0,
    monthDayKey: (item.monthDayKey as string) ?? "",
    weekday: (item.weekday as string) ?? "",
    text: ((item.diaryText as string) || "").trim() || "(no text written)",
    location: (item.locationText as string) || null,
    updatedAt: (item.updatedAt as string) ?? "",
    checkIns: [],
    photoCount: 0,
  };
}

function formatCheckInValue(ci: CheckIn): string {
  if (ci.boolValue !== undefined) return ci.boolValue ? "Yes" : "No";
  if (ci.textValue !== undefined) return ci.textValue;
  if (ci.numberValue !== undefined) return String(ci.numberValue);
  return "(no value)";
}

function entriesToText(entries: DiaryEntry[]): string {
  if (entries.length === 0) return "No entries found.";
  return entries
    .map((e) => {
      const loc = e.location ? ` — ${e.location}` : "";
      let result = `[${e.weekday}, ${e.monthDayKey}/${e.year}${loc}]\n${e.text}`;
      if (e.checkIns.length > 0) {
        const checkInLines = e.checkIns
          .map((ci) => `  - ${ci.label}: ${formatCheckInValue(ci)}`)
          .join("\n");
        result += `\n\nCheck-ins:\n${checkInLines}`;
      }
      if (e.photoCount > 0) {
        result += `\n\nPhotos: ${e.photoCount} photo${e.photoCount > 1 ? "s" : ""} attached`;
      }
      return result;
    })
    .join("\n\n---\n\n");
}

async function queryByPrefix(userId: string, skPrefix: string): Promise<Record<string, unknown>[]> {
  const dynamo = makeDynamoClient();
  const result = await dynamo.send(
    new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: "userId = :uid AND begins_with(sk, :skp)",
      FilterExpression: "attribute_not_exists(deletedAt)",
      ExpressionAttributeValues: {
        ":uid": { S: userId },
        ":skp": { S: skPrefix },
      },
    })
  );
  return (result.Items ?? []).map((item) => unmarshall(item));
}

async function queryTemplates(userId: string): Promise<Map<string, { label: string; type: string }>> {
  const items = await queryByPrefix(userId, "template#");
  const map = new Map<string, { label: string; type: string }>();
  for (const item of items) {
    const id = item.id as string;
    if (id && item.isActive !== false) {
      map.set(id, { label: (item.label as string) ?? "", type: (item.type as string) ?? "" });
    }
  }
  return map;
}

async function queryPhotos(userId: string): Promise<Map<string, number>> {
  const items = await queryByPrefix(userId, "photo#");
  const countMap = new Map<string, number>();
  for (const item of items) {
    const key = `${item.entryMonthDayKey}#${item.entryYear}`;
    countMap.set(key, (countMap.get(key) ?? 0) + 1);
  }
  return countMap;
}

async function fetchPhotoThumbnails(
  userId: string,
  monthDayKey: string,
  year: number,
): Promise<{ data: string; mimeType: string }[]> {
  const items = await queryByPrefix(userId, "photo#");
  const matched = items.filter(
    (item) => item.entryMonthDayKey === monthDayKey && Number(item.entryYear) === year,
  );

  const s3 = new S3Client({ region: REGION });
  const results: { data: string; mimeType: string }[] = [];

  for (const item of matched) {
    const thumbKey = (item.s3ThumbKey as string) || (item.s3Key as string);
    if (!thumbKey) continue;

    const fullKey = thumbKey.startsWith(`${userId}/`) ? thumbKey : `${userId}/${thumbKey}`;
    const response = await s3.send(
      new GetObjectCommand({ Bucket: BUCKET, Key: fullKey }),
    );
    if (!response.Body) continue;

    const bytes = await response.Body.transformToByteArray();
    const base64 = Buffer.from(bytes).toString("base64");
    results.push({ data: base64, mimeType: "image/jpeg" });
  }

  return results;
}

function attachCheckInsAndPhotos(
  entries: DiaryEntry[],
  checkInItems: Record<string, unknown>[],
  templates: Map<string, { label: string; type: string }>,
  photoCounts: Map<string, number>,
): void {
  const checkInsByEntry = new Map<string, CheckIn[]>();
  for (const ci of checkInItems) {
    const sk = ci.sk as string;
    // sk format: checkin#MM-DD#YYYY#UUID
    const parts = sk.split("#");
    if (parts.length < 4) continue;
    const entryKey = `${parts[1]}#${parts[2]}`;
    const templateId = ci.templateId as string;
    const tmpl = templates.get(templateId);
    const checkIn: CheckIn = {
      templateId,
      label: tmpl?.label ?? templateId,
      type: tmpl?.type ?? "unknown",
      ...(ci.boolValue !== undefined && { boolValue: ci.boolValue as boolean }),
      ...(ci.textValue !== undefined && { textValue: ci.textValue as string }),
      ...(ci.numberValue !== undefined && { numberValue: ci.numberValue as number }),
    };
    const list = checkInsByEntry.get(entryKey) ?? [];
    list.push(checkIn);
    checkInsByEntry.set(entryKey, list);
  }

  for (const entry of entries) {
    const entryKey = `${entry.monthDayKey}#${entry.year}`;
    entry.checkIns = checkInsByEntry.get(entryKey) ?? [];
    entry.photoCount = photoCounts.get(entryKey) ?? 0;
  }
}

async function queryEntries(userId: string, skPrefix: string): Promise<DiaryEntry[]> {
  const [entryItems, checkInItems, templates, photoCounts] = await Promise.all([
    queryByPrefix(userId, skPrefix),
    queryByPrefix(userId, skPrefix.replace("entry#", "checkin#")),
    queryTemplates(userId),
    queryPhotos(userId),
  ]);

  const entries = entryItems.map(formatEntry);
  attachCheckInsAndPhotos(entries, checkInItems, templates, photoCounts);
  return entries.sort((a, b) => a.date.localeCompare(b.date));
}

function todayMonthDay(): string {
  const now = new Date();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  return `${mm}-${dd}`;
}

function parseDate(iso: string): { monthDay: string; year: string } {
  const parts = iso.split("-");
  if (parts.length !== 3) throw new Error("Date must be YYYY-MM-DD");
  return { monthDay: `${parts[1]}-${parts[2]}`, year: parts[0] };
}

// ---- MCP Server factory ----------------------------------------------------

export function createServer(): Server {
  const userId = process.env.DIARY_USER_ID;
  if (!userId) throw new Error("DIARY_USER_ID environment variable is required");

  const server = new Server(
    { name: "forever-diary", version: "1.0.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "get_today_entry",
        description: "Get today's diary entry from Forever Diary.",
        inputSchema: { type: "object" as const, properties: {}, required: [] },
      },
      {
        name: "get_entry_by_date",
        description: "Get a diary entry for a specific date (YYYY-MM-DD).",
        inputSchema: {
          type: "object" as const,
          properties: {
            date: { type: "string", description: "Date in YYYY-MM-DD format" },
          },
          required: ["date"],
        },
      },
      {
        name: "get_entries_on_this_day",
        description: "Get all diary entries written on today's month and day across every year.",
        inputSchema: { type: "object" as const, properties: {}, required: [] },
      },
      {
        name: "get_entry_photos",
        description: "Get photo thumbnails attached to a diary entry for a specific date (YYYY-MM-DD). Returns images that can be viewed directly.",
        inputSchema: {
          type: "object" as const,
          properties: {
            date: { type: "string", description: "Date in YYYY-MM-DD format" },
          },
          required: ["date"],
        },
      },
      {
        name: "get_recent_entries",
        description: "Get the most recent diary entries.",
        inputSchema: {
          type: "object" as const,
          properties: {
            days: { type: "number", description: "Number of past days to fetch (default 7, max 30)" },
          },
          required: [],
        },
      },
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    const { name, arguments: args } = req.params;

    try {
      if (name === "get_today_entry") {
        const today = todayMonthDay();
        const year = new Date().getFullYear();
        const entries = await queryEntries(userId, `entry#${today}#${year}`);
        return { content: [{ type: "text" as const, text: entriesToText(entries) }] };
      }

      if (name === "get_entry_by_date") {
        const { date } = args as { date: string };
        const { monthDay, year } = parseDate(date);
        const entries = await queryEntries(userId, `entry#${monthDay}#${year}`);
        return { content: [{ type: "text" as const, text: entriesToText(entries) }] };
      }

      if (name === "get_entries_on_this_day") {
        const today = todayMonthDay();
        const entries = await queryEntries(userId, `entry#${today}#`);
        const header = entries.length > 0 ? `All entries for ${today} across years:\n\n` : "";
        return { content: [{ type: "text" as const, text: header + entriesToText(entries) }] };
      }

      if (name === "get_entry_photos") {
        const { date } = args as { date: string };
        const { monthDay, year } = parseDate(date);
        const photos = await fetchPhotoThumbnails(userId, monthDay, Number(year));
        if (photos.length === 0) {
          return { content: [{ type: "text" as const, text: `No photos found for ${date}.` }] };
        }
        const content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[] = [
          { type: "text" as const, text: `${photos.length} photo${photos.length > 1 ? "s" : ""} from ${date}:` },
        ];
        for (const photo of photos) {
          content.push({ type: "image" as const, data: photo.data, mimeType: photo.mimeType });
        }
        return { content };
      }

      if (name === "get_recent_entries") {
        const { days = 7 } = (args ?? {}) as { days?: number };
        const limit = Math.min(Math.max(1, days), 30);

        // Build per-day prefixes
        const dayPrefixes: { entry: string; checkin: string }[] = [];
        for (let i = 0; i < limit; i++) {
          const d = new Date();
          d.setDate(d.getDate() - i);
          const mm = String(d.getMonth() + 1).padStart(2, "0");
          const dd = String(d.getDate()).padStart(2, "0");
          const year = d.getFullYear();
          dayPrefixes.push({
            entry: `entry#${mm}-${dd}#${year}`,
            checkin: `checkin#${mm}-${dd}#${year}`,
          });
        }

        // Query all days + templates + photos in parallel
        const entryQueries = dayPrefixes.map((p) => queryByPrefix(userId, p.entry));
        const checkInQueries = dayPrefixes.map((p) => queryByPrefix(userId, p.checkin));
        const [templates, photoCounts, ...results] = await Promise.all([
          queryTemplates(userId),
          queryPhotos(userId),
          ...entryQueries,
          ...checkInQueries,
        ]);

        const entryResults = results.slice(0, dayPrefixes.length) as Record<string, unknown>[][];
        const checkInResults = results.slice(dayPrefixes.length) as Record<string, unknown>[][];

        const allEntryItems = entryResults.flat();
        const allCheckInItems = checkInResults.flat();

        const allEntries = allEntryItems.map(formatEntry);
        attachCheckInsAndPhotos(
          allEntries,
          allCheckInItems,
          templates as Map<string, { label: string; type: string }>,
          photoCounts as Map<string, number>,
        );
        allEntries.sort((a, b) => b.date.localeCompare(a.date));
        return { content: [{ type: "text" as const, text: entriesToText(allEntries) }] };
      }

      return {
        content: [{ type: "text" as const, text: `Unknown tool: ${name}` }],
        isError: true,
      };
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      return { content: [{ type: "text" as const, text: `Error: ${msg}` }], isError: true };
    }
  });

  return server;
}
