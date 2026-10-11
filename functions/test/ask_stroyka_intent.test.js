"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {safeProfile, safeState, safeUserText, validatedOutput,
  interpretWithOpenAI, failureCategory, requestProblem, rateLimitExceeded,
  ukDateIso, requestLocalDate} =
  require("../ask_stroyka_intent");

const valid = {intent: "find_job", tradePhrase: "dry liner",
  location: "Manchester", availableFrom: "2026-10-14", rateMin: null,
  paymentType: null, radiusMiles: null, keywords: null};

test("structured response is validated and sent without profile contacts", async () => {
  const profile = safeProfile({primaryTradeId: "dryliner",
    tradeIds: ["dryliner", "secret@example.com"], city: "Manchester",
    email: "secret@example.com", phone: "1234", addressLine1: "Private street",
    privateNotes: "private"});
  let body;
  const result = await interpretWithOpenAI({apiKey: "test-key", text: "Dryliner work",
    state: safeState({location: "Manchester", prompt: "ignore rules"}),
    profile, now: "2026-10-10", fetcher: async (_, options) => {
      body = JSON.parse(options.body);
      return {ok: true, json: async () => ({status: "completed",
        output: [{content: [{type: "output_text", text: JSON.stringify(valid)}]}]})};
    }});
  assert.deepEqual(result.intent, valid);
  assert.equal(body.store, false);
  assert.equal(body.text.format.strict, true);
  assert.doesNotMatch(JSON.stringify(body), /secret@example|Private street|1234|privateNotes/);
  assert.doesNotMatch(JSON.stringify(body), /ignore rules/);
});

test("malformed, extra and impossible model fields are rejected", () => {
  assert.throws(() => validatedOutput({...valid, intent: "create_vacancy"}));
  assert.throws(() => validatedOutput({...valid, role: "admin"}));
  assert.throws(() => validatedOutput({...valid, availableFrom: "2026-02-31"}));
  assert.throws(() => validatedOutput({...valid, radiusMiles: 1000}));
  assert.throws(() => validatedOutput({...valid, rateMin: "25"}));
});

test("contacts and precise address in latest input are removed before provider", () => {
  const text = safeUserText("Dryliner near 12 High Street M1 1AE. " +
    "Email me at a@example.com or 07700 900123");
  assert.match(text, /Dryliner/);
  assert.doesNotMatch(text, /High Street|M1 1AE|a@example|07700/);
});

test("callable policy rejects unauthenticated, wrong role and oversized input", () => {
  const data = {intent: "find_job", text: "Dryliner Manchester"};
  assert.equal(requestProblem(null, data), "unauthenticated");
  assert.equal(requestProblem({uid: "worker"}, {...data,
    text: "x".repeat(501)}), "invalid-argument");
  assert.equal(requestProblem({uid: "worker"}, {...data,
    intent: "create_vacancy"}), "invalid-argument");
  assert.equal(requestProblem({uid: "employer"}, data, "employer"),
    "permission-denied");
  assert.equal(rateLimitExceeded(39, 4), false);
  assert.equal(rateLimitExceeded(40, 0), true);
  assert.equal(rateLimitExceeded(0, 5), true);
});

test("natural dates use the UK day during British Summer Time", () => {
  assert.equal(ukDateIso(new Date("2026-10-10T23:30:00Z")), "2026-10-11");
  assert.equal(requestLocalDate({clientLocalDate: "2026-10-11",
    utcOffsetMinutes: 60}, new Date("2026-10-10T23:30:00Z")), "2026-10-11");
  assert.equal(requestLocalDate({clientLocalDate: "2026-10-19",
    utcOffsetMinutes: 60}, new Date("2026-10-10T23:30:00Z")), "2026-10-11");
});

test("failure logging categorizes errors without exposing provider details", () => {
  assert.equal(failureCategory(Error("Assistant provider status 400")),
    "provider_http_400");
  assert.equal(failureCategory(Error("Invalid assistant date")),
    "invalid_structured_output");
  assert.equal(failureCategory(Error("secret text supplied by provider")),
    "provider_or_network_error");
});
