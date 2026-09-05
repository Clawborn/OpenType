/** Opt-in live evaluation. Reads a local provider config, prints only synthetic
 * prompts and model answers. Never prints credentials or saves conversations. */
import { readFile } from "node:fs/promises";
import { createOpenAICompatibleClient } from "../src/provider/openaiCompatible";
import { createAnthropicClient } from "../src/provider/anthropic";
import { ASK_SYSTEM_PROMPT, AGENT_SYSTEM_PROMPT } from "../src/oneshot/prompts";
import type { LLMProviderConfig } from "../src/provider/types";

const path = process.argv[2];
if (!path) throw new Error("Usage: bun scripts/eval-response-style.ts <local-provider-config.json>");
const { llm } = JSON.parse(await readFile(path, "utf8")) as { llm: LLMProviderConfig };
if (!llm) throw new Error("No configured LLM");
const client = llm.type === "anthropic" ? createAnthropicClient(llm) : createOpenAICompatibleClient(llm);
const cases = [
  { mode: "ask", prompt: "你好", system: ASK_SYSTEM_PROMPT },
  { mode: "agent", prompt: "你好你好你好", system: AGENT_SYSTEM_PROMPT },
  { mode: "ask", prompt: "用一句话解释什么是 API。", system: ASK_SYSTEM_PROMPT },
  { mode: "agent", prompt: "帮我写一条英文消息，告诉同事我会晚到十分钟。只要消息正文，不要发送。", system: AGENT_SYSTEM_PROMPT },
];
for (const item of cases) {
  try {
    const result = await client.chat([
      { role: "system", content: item.system },
      { role: "user", content: item.prompt },
    ]);
    console.log(JSON.stringify({ mode: item.mode, input: item.prompt, output: result.content }));
  } catch {
    console.error(`Live evaluation failed for ${item.mode}; provider details withheld.`);
    process.exitCode = 1;
  }
}
