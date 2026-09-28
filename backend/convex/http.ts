import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { freeChatCompletion } from "./freeAi";

// AI proxy for generated apps: forwards /ai/* to the free model chain
// (Gemini → Groq → OpenRouter) with the key injected server-side, so no
// generated app ever contains a key. Generated web apps call it from the
// browser (hence CORS *); generated iOS apps call it via URLSession.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const http = httpRouter();

http.route({
  pathPrefix: "/ai/",
  method: "OPTIONS",
  handler: httpAction(async () => {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }),
});

http.route({
  pathPrefix: "/ai/",
  method: "POST",
  handler: httpAction(async (_ctx, request) => {
    const url = new URL(request.url);
    const suffix = url.pathname.replace(/^\/ai\//, "");
    if (!/^[a-z0-9/_-]+$/i.test(suffix)) {
      return new Response(JSON.stringify({ error: "bad path" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
    const body = await request.text();
    if (body.length > 1_000_000) {
      return new Response(JSON.stringify({ error: "request too large" }), {
        status: 413,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(body);
    } catch {
      return new Response(JSON.stringify({ error: "invalid JSON body" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
    // Only chat completions are served; the model id is rewritten to the
    // free chain inside freeChatCompletion.
    if (!suffix.toLowerCase().endsWith("chat/completions")) {
      return new Response(JSON.stringify({ error: "unsupported endpoint" }), {
        status: 404,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
    const { status, body: text } = await freeChatCompletion(payload);
    return new Response(text, {
      status,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }),
});

export default http;
