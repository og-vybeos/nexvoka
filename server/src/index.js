/**
 * Nexvoka orchestrator — Express server
 * Fans a user message out to Anthropic, OpenAI, and Google in shared context.
 * Deploy target: Railway (persistent server + Postgres add-on).
 *
 * Status: skeleton. Round sequencing mirrors prototype/index.html.
 */
import express from 'express';
import cors from 'cors';
import 'dotenv/config';

const app = express();
app.use(cors());
app.use(express.json({ limit: '1mb' }));

const PORT = process.env.PORT || 3001;

// ── Provider callers ────────────────────────────────────────────
async function callAnthropic(system, user) {
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-5',
      max_tokens: 1024,
      system,
      messages: [{ role: 'user', content: user }],
    }),
  });
  const d = await r.json();
  if (d.error) throw new Error(d.error.message);
  return d.content[0].text;
}

async function callOpenAI(system, user) {
  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'gpt-4o',
      max_tokens: 1024,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
    }),
  });
  const d = await r.json();
  if (d.error) throw new Error(d.error.message);
  return d.choices[0].message.content;
}

async function callGemini(system, user) {
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${process.env.GOOGLE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: system }] },
        contents: [{ role: 'user', parts: [{ text: user }] }],
      }),
    }
  );
  const d = await r.json();
  if (d.error) throw new Error(d.error.message);
  return d.candidates[0].content.parts[0].text;
}

const PROVIDERS = {
  claude: callAnthropic,
  gpt: callOpenAI,
  gemini: callGemini,
};

const PERSONAS = {
  claude: 'You are Claude at Nexvoka, a multi-AI council. Thoughtful, nuanced, honest about uncertainty. 2-3 concise paragraphs.',
  gpt: 'You are ChatGPT at Nexvoka, a multi-AI council. Practical, direct, action-oriented. 2-3 concise paragraphs.',
  gemini: 'You are Gemini at Nexvoka, a multi-AI council. Data-driven, cross-domain. 2-3 concise paragraphs.',
};

// ── Round endpoint: sequential fan-out with shared context ─────
app.post('/api/round', async (req, res) => {
  const { message, priorContext = '', members = ['claude', 'gpt', 'gemini'], modeInstruction = '' } = req.body;
  if (!message) return res.status(400).json({ error: 'message required' });

  // SSE so the client renders each member as it completes
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  const transcript = [];
  for (const member of members) {
    try {
      const others = transcript.map(t => `${t.member} said: ${t.text}`).join('\n');
      const ctx = [priorContext, others && `Council members already responded:\n${others}`, `User: ${message}`]
        .filter(Boolean)
        .join('\n\n');
      const text = await PROVIDERS[member](`${PERSONAS[member]}\n\n${modeInstruction}`, ctx);
      transcript.push({ member, text });
      res.write(`data: ${JSON.stringify({ member, text })}\n\n`);
    } catch (err) {
      res.write(`data: ${JSON.stringify({ member, error: err.message })}\n\n`);
    }
  }
  res.write('data: [DONE]\n\n');
  res.end();
});

app.get('/health', (_req, res) => res.json({ ok: true, service: 'nexvoka-orchestrator' }));

app.listen(PORT, () => console.log(`Nexvoka orchestrator on :${PORT}`));
