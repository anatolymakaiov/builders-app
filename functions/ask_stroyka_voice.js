"use strict";

const MAX_AUDIO_BYTES = 2 * 1024 * 1024;
const MAX_DURATION_MS = 30000;

function mp4DurationMs(audio) {
  function boxes(start, end) {
    let offset = start;
    while (offset + 8 <= end) {
      const size = audio.readUInt32BE(offset);
      if (size < 8 || offset + size > end) return null;
      const type = audio.toString("ascii", offset + 4, offset + 8);
      if (type === "moov") {
        const duration = boxes(offset + 8, offset + size);
        if (duration !== null) return duration;
      }
      if (type === "mvhd") {
        const payload = offset + 8;
        const version = audio[payload];
        const scaleAt = payload + (version === 0 ? 12 : 20);
        const durationAt = payload + (version === 0 ? 16 : 24);
        if (version > 1 || durationAt + (version === 0 ? 4 : 8) > offset + size) {
          return null;
        }
        const timescale = audio.readUInt32BE(scaleAt);
        const ticks = version === 0 ? audio.readUInt32BE(durationAt) :
          Number(audio.readBigUInt64BE(durationAt));
        if (!timescale || !Number.isSafeInteger(ticks)) return null;
        return Math.round(ticks * 1000 / timescale);
      }
      offset += size;
    }
    return null;
  }
  return boxes(0, audio.length);
}

function validateVoiceRequest(auth, data) {
  if (!auth?.uid) return {problem: "unauthenticated"};
  if (!data || data.mimeType !== "audio/mp4" ||
      !Number.isInteger(data.durationMs) || data.durationMs < 500 ||
      data.durationMs > MAX_DURATION_MS ||
      typeof data.audioBase64 !== "string" ||
      data.audioBase64.length > Math.ceil(MAX_AUDIO_BYTES / 3) * 4 + 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data.audioBase64)) {
    return {problem: "invalid-argument"};
  }
  const audio = Buffer.from(data.audioBase64, "base64");
  if (audio.length < 128 || audio.length > MAX_AUDIO_BYTES) {
    return {problem: "invalid-argument"};
  }
  const actualDurationMs = mp4DurationMs(audio);
  if (actualDurationMs === null || actualDurationMs < 500 ||
      actualDurationMs > MAX_DURATION_MS ||
      Math.abs(actualDurationMs - data.durationMs) > 3000) {
    return {problem: "invalid-argument"};
  }
  return {audio, durationMs: data.durationMs};
}

async function transcribeWithOpenAI({apiKey, audio, fetcher = fetch}) {
  const form = new FormData();
  form.append("file", new Blob([audio], {type: "audio/mp4"}), "voice.m4a");
  form.append("model", "gpt-4o-mini-transcribe");
  form.append("response_format", "json");
  const response = await fetcher("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {Authorization: `Bearer ${apiKey}`},
    body: form,
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`Transcription provider status ${response.status}`);
  const body = await response.json();
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (text.length > 500) throw new Error("Invalid transcription length");
  return text;
}

module.exports = {validateVoiceRequest, transcribeWithOpenAI, mp4DurationMs,
  MAX_AUDIO_BYTES, MAX_DURATION_MS};
