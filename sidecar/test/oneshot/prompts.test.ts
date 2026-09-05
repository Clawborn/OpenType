import { describe, expect, test } from "bun:test";
import { AGENT_SYSTEM_PROMPT, ASK_SYSTEM_PROMPT } from "../../src/oneshot/prompts";

describe("conversational response style", () => {
  for (const [name, prompt] of [["ask", ASK_SYSTEM_PROMPT], ["agent", AGENT_SYSTEM_PROMPT]]) {
    test(`${name} follows the current user's language and keeps simple exchanges brief`, () => {
      expect(prompt).toContain("Reply in the language of the user's current message");
      expect(prompt).toContain("unless the user explicitly requests another language");
      expect(prompt).toContain("For a greeting or a simple acknowledgement, use one short sentence");
      expect(prompt).toContain("Do not advertise your capabilities");
      expect(prompt).toContain("UNTRUSTED");
    });
  }
  test("agent distinguishes an actual completed action from a draft", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("Never claim an action succeeded without a confirming tool result");
    expect(AGENT_SYSTEM_PROMPT).not.toContain("this is a draft for the user to review, not an action taken");
  });
});

describe("AGENT_SYSTEM_PROMPT", () => {
  test("tells the model when to call remember_fact, including the Chinese 记住 trigger", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("remember_fact");
    expect(AGENT_SYSTEM_PROMPT).toContain("记住");
  });

  test("tells the model when to call consolidate_memory_now, including a Chinese trigger", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("consolidate_memory_now");
    expect(AGENT_SYSTEM_PROMPT).toMatch(/整理|回顾/);
  });
});

/**
 * B2 core tools v2 prompt changes
 * (docs/superpowers/specs/2026-08-13-b2-agent-core-tools-v2-design.md §5):
 * the v1 "no-side-effect tools only" framing is retired, the prompt now
 * describes real capabilities with the home directory as the default working
 * location and Desktop/Downloads-first file guidance -- while the
 * prompt-injection-defense (UNTRUSTED) paragraph and the memory-tools
 * paragraph must survive unchanged.
 */
describe("AGENT_SYSTEM_PROMPT (core tools v2)", () => {
  test("no longer claims only side-effect-free tools are connected", () => {
    expect(AGENT_SYSTEM_PROMPT).not.toContain("no side effects");
  });

  test("names the home directory as the default working location", () => {
    // Contract: the implementation is expected to include the literal phrase
    // "home directory" when describing where the agent works by default.
    expect(AGENT_SYSTEM_PROMPT).toContain("home directory");
  });

  test("tells the agent to look in Desktop and Downloads first for unlocated files", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("Desktop");
    expect(AGENT_SYSTEM_PROMPT).toContain("Downloads");
  });

  test("keeps the prompt-injection defense (UNTRUSTED) and the memory-tools guidance", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("UNTRUSTED");
    expect(AGENT_SYSTEM_PROMPT).toContain("remember_fact");
  });
});

/**
 * B2 open-file + ask-web prompt changes
 * (docs/superpowers/specs/2026-08-13-b2-open-file-and-ask-web-design.md):
 * §1 -- AGENT_SYSTEM_PROMPT gains open_file guidance: when the user asks to
 * open, preview, play, or "看一下" a file, the agent should find it and call
 * `opentype__open_file` -- opening it for the user IS the requested outcome,
 * not just reporting the path.
 * §2 -- the ask prompt gains web-capability guidance, and (new contract) the
 * UNTRUSTED-data defense: checked 2026-08-13, the current ASK_SYSTEM_PROMPT
 * has NO untrusted-data paragraph at all, and once Ask can fetch arbitrary
 * web pages that content is prompt-injection surface #1, so the defense is
 * added rather than preserved.
 */
describe("AGENT_SYSTEM_PROMPT (open_file, open-file design §1)", () => {
  test("tells the agent to call open_file to open/preview/play files for the user, not just report the path", () => {
    expect(AGENT_SYSTEM_PROMPT).toContain("open_file");
    expect(AGENT_SYSTEM_PROMPT).toMatch(/preview|play/i);
  });
});

/**
 * Showing the file is the deliverable, not an extra.
 *
 * The earlier guidance triggered off a verb allowlist ("asks you to open,
 * preview, play, or look at"), so the phrasings people actually use --
 * "帮我找一下那个文件", "那个 PDF 在哪", "给我看看" -- fell outside it and the
 * agent answered with a path. A path is not what was wanted: the user is
 * speaking BECAUSE they want the thing in front of them.
 *
 * These tests pin the widened trigger and the restraint that has to come with
 * it, so a later edit cannot quietly narrow either one back.
 */
describe("AGENT_SYSTEM_PROMPT (preview-first)", () => {
  test("covers finding and locating a file, not only being told to open one", () => {
    expect(AGENT_SYSTEM_PROMPT).toMatch(/找/);
    expect(AGENT_SYSTEM_PROMPT).toMatch(/看/);
  });

  test("states that showing the file is the outcome, so a path alone is not an answer", () => {
    expect(AGENT_SYSTEM_PROMPT).toMatch(/path/i);
    expect(AGENT_SYSTEM_PROMPT).toMatch(/open_file/);
  });

  test("routes an ambiguous match to ask_user instead of opening everything", () => {
    // Without this the widened trigger turns "find my invoice" into a screen
    // full of Preview windows -- the failure mode of being MORE eager.
    expect(AGENT_SYSTEM_PROMPT).toContain("ask_user");
  });

  test("keeps a boundary so questions answerable in text stay in text", () => {
    // "how many PDFs are on my desktop" is a question, not a request to see
    // one; opening files to answer it would be worse than not opening any.
    expect(AGENT_SYSTEM_PROMPT).toMatch(/count|list|question/i);
  });
});

describe("ASK_SYSTEM_PROMPT (web, ask-web design §2)", () => {
  test("mentions the web search capability", () => {
    expect(ASK_SYSTEM_PROMPT).toMatch(/web/i);
    expect(ASK_SYSTEM_PROMPT).toMatch(/search/i);
  });

  test("treats web content as UNTRUSTED data (prompt-injection defense)", () => {
    expect(ASK_SYSTEM_PROMPT).toContain("UNTRUSTED");
  });

  test("still frames Ask as the one mode that answers the question directly", () => {
    // Guard, green before and after: the web extension must not displace the
    // mode's identity as a direct, concise answerer.
    expect(ASK_SYSTEM_PROMPT).toMatch(/answer/i);
  });
});
