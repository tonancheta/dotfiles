#!/usr/bin/env node
import OpenAI from "openai";

const prompt = process.argv.slice(2).join(" ");

if (!prompt) {
  console.error("Usage: qwen.mjs <prompt>");
  process.exit(1);
}

if (!process.env.QWEN_API_KEY) {
  console.error("Error: QWEN_API_KEY is not set.");
  process.exit(1);
}

const client = new OpenAI({
  apiKey: process.env.QWEN_API_KEY,
  baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
});

try {
  const response = await client.chat.completions.create({
    model: "qwen3.8-flash",
    messages: [{ role: "user", content: prompt }],
  });
  console.log(response.choices[0].message.content);
} catch (err) {
  console.error("Qwen API error:", err.message || String(err));
  process.exit(1);
}
