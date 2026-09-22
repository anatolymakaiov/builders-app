"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  selectAuthorizedAccountLinkGroup,
} = require("../account_linking");

test("same-group linked accounts are authorized", () => {
  assert.equal(
    selectAuthorizedAccountLinkGroup("source", "target", [
      {
        groupId: "group-a",
        exists: true,
        memberIds: ["source", "target"],
      },
    ]),
    "group-a",
  );
});

test("different-group target is rejected", () => {
  assert.equal(
    selectAuthorizedAccountLinkGroup("source", "target", [
      { groupId: "group-a", exists: true, memberIds: ["source"] },
      { groupId: "group-b", exists: true, memberIds: ["target"] },
    ]),
    null,
  );
});

test("missing membership is rejected", () => {
  assert.equal(
    selectAuthorizedAccountLinkGroup("source", "target", [
      { groupId: "group-a", exists: true, memberIds: ["source"] },
    ]),
    null,
  );
});

test("authoritative group membership tolerates a stale member pointer", () => {
  assert.equal(
    selectAuthorizedAccountLinkGroup("source", "target", [
      {
        groupId: "group-a",
        exists: true,
        memberIds: ["source", "target"],
      },
      { groupId: "stale-group", exists: false, memberIds: [] },
    ]),
    "group-a",
  );
});

test("ambiguous duplicate group membership is rejected for repair", () => {
  assert.equal(
    selectAuthorizedAccountLinkGroup("source", "target", [
      {
        groupId: "group-a",
        exists: true,
        memberIds: ["source", "target"],
      },
      {
        groupId: "group-b",
        exists: true,
        memberIds: ["source", "target"],
      },
    ]),
    "ambiguous",
  );
});
