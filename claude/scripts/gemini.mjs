#!/usr/bin/env node
import { GoogleGenAI } from "@google/genai";

const prompt = process.argv.slice(2).join(" ");

if (!prompt) {
  console.error("Usage: gemini.mjs <prompt>");
  process.exit(1);
}

if (!process.env.GEMINI_API_KEY) {
  console.error("Error: GEMINI_API_KEY is not set.");
  process.exit(1);
}

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

try {
  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash",
    contents: prompt,
  });
  console.log(response.text);
} catch (err) {
  console.error("Gemini API error:", err.message || String(err));
  process.exit(1);
}
