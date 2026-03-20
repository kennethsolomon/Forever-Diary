import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";
import { unmarshall } from "@aws-sdk/util-dynamodb";

// ---- Config ----------------------------------------------------------------

const TABLE = process.env.DYNAMODB_TABLE ?? "forever-diary";
const REGION = process.env.AWS_REGION ?? "ap-southeast-1";

// ---- DynamoDB client -------------------------------------------------------

function makeDynamoClient() {
  return new DynamoDBClient({ region: REGION });
}

// ---- Helpers ---------------------------------------------------------------

interface DiaryEntry {
  date: string;
  year: number;
  monthDayKey: string;
  weekday: string;
  text: string;
  location: string | null;
  updatedAt: string;
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
  };
}

function entriesToText(entries: DiaryEntry[]): string {
  if (entries.length === 0) return "No entries found.";
  return entries
    .map((e) => {
      const loc = e.location ? ` — ${e.location}` : "";
      return `[${e.weekday}, ${e.monthDayKey}/${e.year}${loc}]\n${e.text}`;
    })
    .join("\n\n---\n\n");
}

async function queryEntries(userId: string, skPrefix: string): Promise<DiaryEntry[]> {
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
  return (result.Items ?? [])
    .map((item) => unmarshall(item))
    .map(formatEntry)
    .sort((a, b) => a.date.localeCompare(b.date));
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

      if (name === "get_recent_entries") {
        const { days = 7 } = (args ?? {}) as { days?: number };
        const limit = Math.min(Math.max(1, days), 30);
        const allEntries: DiaryEntry[] = [];

        for (let i = 0; i < limit; i++) {
          const d = new Date();
          d.setDate(d.getDate() - i);
          const mm = String(d.getMonth() + 1).padStart(2, "0");
          const dd = String(d.getDate()).padStart(2, "0");
          const year = d.getFullYear();
          const entries = await queryEntries(userId, `entry#${mm}-${dd}#${year}`);
          allEntries.push(...entries);
        }

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
