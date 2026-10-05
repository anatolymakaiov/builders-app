"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {publicProfile, workerDiscovery} = require("../profile_projections");

const worker = {
  role: "worker", profileComplete: true, active: true,
  name: "Anthony Mackay", trade: "Dryliner", tradeIds: ["dryliner"],
  primaryTradeId: "dryliner", townCity: "Manchester",
  county: "Greater Manchester", phone: "+44 7700 900123",
  email: "private@example.com", addressLine1: "1 Private Street",
  location: "1 Private Street", postcode: "M1 1AA",
  lat: 53.481, lng: -2.241, dateOfBirth: "1980-01-01",
  authPreferences: {secret: "private"}, token: "private",
  availabilityStatus: "open_to_work", allowVacancyInvites: false,
};

test("allowlist excludes private contact, home and account data", () => {
  for (const projection of [publicProfile("w1", worker), workerDiscovery("w1", worker)]) {
    const json = JSON.stringify(projection);
    for (const secret of ["private@example.com", "+44 7700 900123",
      "Private Street", "M1 1AA", "53.481", "1980-01-01", "secret"]) {
      assert.equal(json.includes(secret), false, secret);
    }
  }
});

test("legacy availability is unknown and invitations remain disabled", () => {
  const profile = workerDiscovery("w1", worker);
  assert.equal(profile.availabilityStatus, "unknown");
  assert.equal(profile.allowVacancyInvites, false);
  assert.equal(profile.displayNameShort, "Anthony M.");
  assert.deepEqual(profile.tradeIds, ["dryliner"]);
});

test("confirmed canonical availability is projected without residential coordinates", () => {
  const profile = workerDiscovery("w1", {
    ...worker, availabilityStatus: "available_from",
    availabilityConfirmedAt: "2026-10-05", availableFrom: "2026-10-21",
    allowVacancyInvites: true,
  });
  assert.equal(profile.availabilityStatus, "available_from");
  assert.equal(profile.availableFrom, "2026-10-21");
  assert.equal(profile.generalArea, "Manchester");
  assert.equal("lat" in profile, false);
  assert.equal("lng" in profile, false);
});

test("incomplete and non-worker profiles are not discoverable", () => {
  assert.equal(workerDiscovery("w1", {...worker, profileComplete: false}), null);
  assert.equal(workerDiscovery("e1", {...worker, role: "employer"}), null);
  assert.equal(publicProfile("a1", {...worker, role: "admin"}), null);
});

test("projection is deterministic for idempotent backfill", () => {
  assert.deepEqual(publicProfile("w1", worker), publicProfile("w1", worker));
  assert.deepEqual(workerDiscovery("w1", worker), workerDiscovery("w1", worker));
  const employer = {...worker, role: "employer", companyName: "Build Co"};
  assert.equal(workerDiscovery("e1", employer), null);
  assert.equal(publicProfile("e1", employer).displayName, "Build Co");
});

test("street-like town values are not projected", () => {
  const data = {...worker, townCity: "High Street", bio: "Call +44 7700 900123"};
  assert.equal(workerDiscovery("w1", data).generalArea, "");
  assert.equal(publicProfile("w1", data).townCity, "");
  assert.equal(JSON.stringify(publicProfile("w1", data)).includes("7700"), false);
});

test("free-form text cannot leak through date fields", () => {
  const data = {...worker, availabilityStatus: "available_from",
    availabilityConfirmedAt: "Call +44 7700 900123",
    availabilityUpdatedAt: "private@example.com",
    availableFrom: "1 Private Street", updatedAt: "private@example.com"};
  for (const projection of [publicProfile("w1", data), workerDiscovery("w1", data)]) {
    const json = JSON.stringify(projection);
    assert.equal(json.includes("7700"), false);
    assert.equal(json.includes("private@example.com"), false);
    assert.equal(json.includes("Private Street"), false);
  }
  assert.equal(workerDiscovery("w1", data).availabilityStatus, "unknown");
});
