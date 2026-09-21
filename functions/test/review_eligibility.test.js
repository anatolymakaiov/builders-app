"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  effectiveApplicationStatusForWorker,
  hasAcceptedWorkRelationship,
} = require("../review_eligibility");

const workerId = "worker-1";

test("membersStatus accepted overrides pending application status", () => {
  const application = {
    type: "team",
    status: "pending",
    membersStatus: { [workerId]: " Accepted " },
  };
  assert.equal(effectiveApplicationStatusForWorker(application, workerId), "accepted");
  assert.equal(hasAcceptedWorkRelationship(application, workerId), true);
});

test("legacy memberStatuses hired overrides negotiation", () => {
  const application = {
    teamId: "team-1",
    status: "negotiation",
    memberStatuses: { [workerId]: "HIRED" },
  };
  assert.equal(effectiveApplicationStatusForWorker(application, workerId), "hired");
  assert.equal(hasAcceptedWorkRelationship(application, workerId), true);
});

test("individual application falls back to accepted status", () => {
  const application = { workerId, status: " accepted " };
  assert.equal(hasAcceptedWorkRelationship(application, workerId), true);
});

test("member rejection overrides accepted team status", () => {
  const application = {
    type: "team",
    status: "accepted",
    membersStatus: { [workerId]: "rejected" },
  };
  assert.equal(hasAcceptedWorkRelationship(application, workerId), false);
});

test("pending member remains ineligible", () => {
  const application = {
    type: "team",
    status: "pending",
    membersStatus: { [workerId]: "pending" },
  };
  assert.equal(hasAcceptedWorkRelationship(application, workerId), false);
});

test("another accepted member does not qualify the requesting Worker", () => {
  const application = {
    type: "team",
    status: "accepted",
    membersStatus: {
      [workerId]: "pending",
      "worker-2": "accepted",
    },
  };
  assert.equal(hasAcceptedWorkRelationship(application, workerId), false);
});

test("a Worker outside the application is ineligible", () => {
  const application = {
    type: "team",
    status: "accepted",
    membersStatus: { "worker-2": "accepted" },
  };
  assert.equal(effectiveApplicationStatusForWorker(application, workerId), "");
  assert.equal(hasAcceptedWorkRelationship(application, workerId), false);
});
