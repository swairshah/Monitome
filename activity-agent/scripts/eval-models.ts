#!/usr/bin/env bun

import { readFileSync, readdirSync } from "fs";
import { join } from "path";
import { Agent } from "@mariozechner/pi-agent-core";
import { getModel } from "@mariozechner/pi-ai";

const SYSTEM_PROMPT = `You are indexing screenshots for a personal activity search engine. Extract SEARCHABLE information.

Extract structured metadata and respond with JSON (no markdown):
{
  "app": { "name": "App", "windowTitle": "Title", "category": "browser|ide|terminal|media|communication|productivity|other" },
  "browser": { "url": "full url", "domain": "domain.com", "pageTitle": "Title", "pageType": "video|article|documentation|code|other" },
  "video": { "platform": "YouTube", "title": "Full Video Title", "channel": "Channel", "duration": "12:34" },
  "ide": { "ide": "VS Code", "currentFile": "file.ts", "filePath": "/full/path", "language": "TypeScript", "projectName": "project" },
  "terminal": { "cwd": "/path", "lastCommand": "npm run build" },
  "activity": "Specific searchable description",
  "summary": "Key searchable content: 1-2 sentences max.",
  "tags": ["searchable", "terms", "technologies"]
}

Focus on SEARCHABILITY - extract exact URLs, titles, file paths, project names.
Only include relevant metadata objects (skip null/empty ones).`;

async function analyzeWithModel(modelId: string, imageBase64: string, mimeType: string): Promise<{ result: string; timeMs: number }> {
  const model = getModel("anthropic", modelId);
  const agent = new Agent({
    initialState: {
      systemPrompt: SYSTEM_PROMPT,
      model,
      messages: [],
    },
  });

  const start = Date.now();
  await agent.prompt("Analyze this screenshot and extract structured metadata.", [
    { type: "image", data: imageBase64, mimeType },
  ]);

  const messages = agent.state.messages;
  const assistantMessage = messages.find((m) => m.role === "assistant");
  
  let result = "";
  if (assistantMessage && "content" in assistantMessage) {
    const textContent = assistantMessage.content.find((c): c is { type: "text"; text: string } => c.type === "text");
    if (textContent) {
      result = textContent.text;
    }
  }

  return { result, timeMs: Date.now() - start };
}

async function compareResults(opusResult: string, haikuResult: string, imageBase64: string, mimeType: string): Promise<string> {
  const model = getModel("anthropic", "claude-opus-4-5");
  const agent = new Agent({
    initialState: {
      systemPrompt: "You are an expert evaluator comparing AI model outputs for screenshot analysis quality.",
      model,
      messages: [],
    },
  });

  const prompt = `I have two AI models analyzing the same screenshot for a personal activity tracker. 
Please compare the outputs and assess:

1. **Accuracy**: Which model extracted more accurate information from the screenshot?
2. **Completeness**: Which model captured more relevant details?
3. **Searchability**: Which output would be more useful for finding this screenshot later?
4. **Errors**: Any hallucinations or mistakes in either output?

## Opus Output:
\`\`\`json
${opusResult}
\`\`\`

## Haiku Output:
\`\`\`json
${haikuResult}
\`\`\`

Provide a brief assessment (2-3 paragraphs) and a final verdict: Is Haiku good enough for this use case, or is Opus significantly better?`;

  await agent.prompt(prompt, [
    { type: "image", data: imageBase64, mimeType },
  ]);

  const messages = agent.state.messages;
  const assistantMessage = messages.find((m) => m.role === "assistant");
  
  if (assistantMessage && "content" in assistantMessage) {
    const textContent = assistantMessage.content.find((c): c is { type: "text"; text: string } => c.type === "text");
    if (textContent) {
      return textContent.text;
    }
  }
  return "No comparison generated";
}

async function main() {
  // Find a screenshot to test
  const dataDir = join(process.env.HOME || "", "Library/Application Support/Monitome/recordings");
  let screenshotPath = process.argv[2];

  if (!screenshotPath) {
    // Pick a random recent screenshot
    const files = readdirSync(dataDir)
      .filter((f) => f.endsWith(".jpg"))
      .sort()
      .reverse();
    
    if (files.length === 0) {
      console.error("No screenshots found in", dataDir);
      process.exit(1);
    }
    
    // Pick one from the middle (not too new, not too old)
    const idx = Math.min(5, Math.floor(files.length / 2));
    screenshotPath = join(dataDir, files[idx]);
    console.log(`Using screenshot: ${files[idx]}\n`);
  }

  // Load image
  const imageData = readFileSync(screenshotPath);
  const imageBase64 = imageData.toString("base64");
  const mimeType = "image/jpeg";

  console.log("=" .repeat(60));
  console.log("MODEL COMPARISON EVAL");
  console.log("=" .repeat(60));

  // Test with Opus
  console.log("\n📊 Testing claude-opus-4-5...");
  const opus = await analyzeWithModel("claude-opus-4-5", imageBase64, mimeType);
  console.log(`   Time: ${opus.timeMs}ms`);
  console.log("\n--- Opus Output ---");
  console.log(opus.result);

  // Test with Haiku
  console.log("\n📊 Testing claude-haiku-4-5...");
  const haiku = await analyzeWithModel("claude-haiku-4-5", imageBase64, mimeType);
  console.log(`   Time: ${haiku.timeMs}ms`);
  console.log("\n--- Haiku Output ---");
  console.log(haiku.result);

  // Compare with Opus as judge
  console.log("\n" + "=" .repeat(60));
  console.log("OPUS EVALUATION (with screenshot context)");
  console.log("=" .repeat(60));
  
  const comparison = await compareResults(opus.result, haiku.result, imageBase64, mimeType);
  console.log("\n" + comparison);

  // Summary
  console.log("\n" + "=" .repeat(60));
  console.log("TIMING SUMMARY");
  console.log("=" .repeat(60));
  console.log(`Opus:  ${opus.timeMs}ms`);
  console.log(`Haiku: ${haiku.timeMs}ms`);
  console.log(`Speedup: ${(opus.timeMs / haiku.timeMs).toFixed(1)}x faster with Haiku`);
}

main().catch(console.error);
