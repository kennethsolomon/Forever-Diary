import express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createServer } from "./server.js";

const app = express();
app.use(express.json());

const API_KEY = process.env.MCP_API_KEY;

// Auth middleware
app.use((req, res, next) => {
  if (req.path === "/health") return next();
  if (API_KEY) {
    const auth = req.headers.authorization;
    if (!auth || auth !== `Bearer ${API_KEY}`) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
  }
  next();
});

// Health check
app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "forever-diary-mcp" });
});

// MCP endpoint — stateless, one server instance per request
app.all("/mcp", async (req, res) => {
  try {
    const server = createServer();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined, // stateless
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
    res.on("finish", () => server.close());
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    if (!res.headersSent) {
      res.status(500).json({ error: msg });
    }
  }
});

const PORT = Number(process.env.PORT ?? 3000);
app.listen(PORT, () => {
  process.stdout.write(`Forever Diary MCP server running on port ${PORT}\n`);
});
