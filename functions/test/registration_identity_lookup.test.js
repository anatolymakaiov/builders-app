"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {identityInUse, normalizePhone} = require("../registration_identity_lookup");

const database = (users, indexes = {}) => ({
  collection(name) {
    return {
      doc(id) {
        return {get: async () => {
          const data = name === "users" ? users[id] : indexes[name]?.[id];
          return {exists: Boolean(data), data: () => data};
        }};
      },
      where(field, operator, value) {
        assert.equal(name, "users");
        return {limit() {
          return {get: async () => ({docs: Object.entries(users)
            .filter(([, data]) => operator === "array-contains"
              ? Array.isArray(data[field]) && data[field].includes(value)
              : data[field] === value)
            .map(([id, data]) => ({id, data: () => data}))})};
        }};
      },
    };
  },
});

test("active foreign email is blocked without returning profile data", async () => {
  const db = database({other: {email: "worker@example.com", active: true}});
  assert.equal(await identityInUse(db, {
    kind: "email", value: "WORKER@example.com", currentUid: "self",
  }), true);
  assert.equal(await identityInUse(db, {
    kind: "email", value: "worker@example.com", currentUid: "other",
  }), false);
  assert.equal(await identityInUse(db, {
    kind: "email", value: "worker@example.com", currentUid: "",
  }), false);
});

test("inactive users and stale indexes do not block registration", async () => {
  const db = database({old: {normalizedEmail: "old@example.com", deleted: true}},
    {emailIndex: {"old@example.com": {uid: "old", active: true}}});
  assert.equal(await identityInUse(db, {
    kind: "email", value: "old@example.com", currentUid: "new",
  }), false);
});

test("phone fallback checks normalized, raw and legacy array forms", async () => {
  assert.equal(normalizePhone("07700 900123"), "+447700900123");
  const db = database({other: {normalizedPhone: "+447700900123"}});
  assert.equal(await identityInUse(db, {
    kind: "phone", value: "07700 900123", currentUid: "self",
  }), true);
  const legacy = database({other: {phones: ["07700 900123"]}});
  assert.equal(await identityInUse(legacy, {
    kind: "phone", value: "07700 900123", currentUid: "self",
  }), true);
});

test("active index still blocks when user fields are missing", async () => {
  const db = database({other: {active: true}},
    {registrationEmailIndex: {"worker@example.com": {uid: "other", active: true}}});
  assert.equal(await identityInUse(db, {
    kind: "email", value: "worker@example.com", currentUid: "self",
  }), true);
  assert.equal(await identityInUse(db, {
    kind: "email", value: "worker@example.com", currentUid: "",
  }), true);
});
