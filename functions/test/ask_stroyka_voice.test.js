"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {validateVoiceRequest, transcribeWithOpenAI} =
  require("../ask_stroyka_voice");

function exampleMp4(durationMs = 2000) {
  const audio = Buffer.alloc(512);
  audio.writeUInt32BE(16, 0);
  audio.write("ftyp", 4);
  audio.write("M4A ", 8);
  audio.writeUInt32BE(36, 16);
  audio.write("moov", 20);
  audio.writeUInt32BE(28, 24);
  audio.write("mvhd", 28);
  audio.writeUInt32BE(1000, 44);
  audio.writeUInt32BE(durationMs, 48);
  audio.writeUInt32BE(460, 52);
  audio.write("free", 56);
  return audio;
}
const audioBase64 = exampleMp4().toString("base64");
const data = {audioBase64, mimeType: "audio/mp4", durationMs: 2000};

test("voice request requires auth and valid bounded audio", () => {
  assert.equal(validateVoiceRequest(null, data).problem, "unauthenticated");
  assert.equal(validateVoiceRequest({uid: "worker"}, data).audio.length, 512);
  for (const invalid of [
    {...data, mimeType: "audio/wav"},
    {...data, durationMs: 30001},
    {...data, durationMs: 0},
    {...data, audioBase64: Buffer.alloc(2 * 1024 * 1024 + 1).toString("base64")},
    {...data, audioBase64: "not base64!"},
    {...data, audioBase64: Buffer.alloc(512).toString("base64")},
    {...data, audioBase64: exampleMp4(31000).toString("base64")},
  ]) {
    assert.equal(validateVoiceRequest({uid: "worker"}, invalid).problem,
      "invalid-argument");
  }
});

test("transcription sends bounded media to mini model and returns text only", async () => {
  let body;
  const text = await transcribeWithOpenAI({apiKey: "test-key",
    audio: Buffer.alloc(512, 1), fetcher: async (url, options) => {
      assert.equal(url, "https://api.openai.com/v1/audio/transcriptions");
      assert.equal(options.headers.Authorization, "Bearer test-key");
      body = options.body;
      return {ok: true, json: async () => ({text: "Dryliner in Manchester"})};
    }});
  assert.equal(body.get("model"), "gpt-4o-mini-transcribe");
  assert.equal(body.get("response_format"), "json");
  assert.equal(text, "Dryliner in Manchester");
});

test("empty speech and provider failure do not expose provider body", async () => {
  const audio = Buffer.alloc(512, 1);
  assert.equal(await transcribeWithOpenAI({apiKey: "test", audio,
    fetcher: async () => ({ok: true, json: async () => ({text: "  "})})}), "");
  await assert.rejects(transcribeWithOpenAI({apiKey: "test", audio,
    fetcher: async () => ({ok: false, status: 429})}),
  /Transcription provider status 429/);
});
