const assert = require("node:assert/strict");
const test = require("node:test");
const {
  matchesProfession, distanceKm, filterDirectoryRecord,
  broadcastTargetId, matchesBroadcastAudience,
} = require("../admin_directory");

test("Dryliner aliases include legacy Dry Liner and Fixer profiles", () => {
  const terms = ["dryliner", "dry liner", "fixer", "drywall fixer"];
  assert.equal(matchesProfession({trade: "Dry Liner"}, terms), true);
  assert.equal(matchesProfession({position: "Fixer"}, terms), true);
  assert.equal(matchesProfession({trade: "Electrician"}, terms), false);
});

test("radius uses postcode coordinates and excludes unlocated profiles", () => {
  const coordinates = new Map([["m11ae", {lat: 53.48, lng: -2.24}]]);
  const filters = {role: "worker", search: "", status: "all",
    professionTerms: [], location: "Manchester",
    origin: {lat: 53.48, lng: -2.24}, radiusKm: 20};
  const near = filterDirectoryRecord("one", {postcode: "M1 1AE"},
    filters, coordinates);
  assert.ok(near);
  assert.ok(near.distanceKm < 1);
  assert.equal(filterDirectoryRecord("two", {city: "Manchester"},
    filters, coordinates), null);
  assert.equal(filterDirectoryRecord("three", {lat: 51.5, lng: -0.1},
    filters, coordinates), null);
  assert.ok(distanceKm({lat: 53.48, lng: -2.24}, {lat: 51.5, lng: -0.1}) > 200);
});

test("location, status and search filters do not match unrelated text", () => {
  const filters = {role: "employer", search: "build", status: "active",
    professionTerms: [], location: "Manchester", origin: null};
  assert.ok(filterDirectoryRecord("one", {companyName: "Build Co",
    city: "Manchester"}, filters, new Map()));
  assert.equal(filterDirectoryRecord("two", {companyName: "Manchester Build",
    city: "Leeds"}, filters, new Map()), null);
  assert.equal(filterDirectoryRecord("three", {companyName: "Build Co",
    city: "Manchester", moderationHold: true}, filters, new Map()), null);
});

test("directory payload omits private fields not needed by list rows", () => {
  const filters = {role: "worker", search: "", status: "all",
    professionTerms: [], location: "", origin: null};
  const entry = filterDirectoryRecord("worker-1", {
    role: "worker", firstName: "Alex", trade: "Dryliner",
    privateSessionToken: "do-not-send", billing: {secret: "hidden"},
  }, filters, new Map());
  assert.equal(entry.data.firstName, "Alex");
  assert.equal(entry.data.privateSessionToken, undefined);
  assert.equal(entry.data.billing, undefined);
  assert.equal(entry.data.email, undefined);
  assert.equal(entry.data.phone, undefined);
});

test("employer directory exposes plan summary but not billing secrets", () => {
  const filters = {role: "employer", search: "", status: "all",
    professionTerms: [], location: "", origin: null};
  const entry = filterDirectoryRecord("employer-1", {
    role: "employer", companyName: "Build Co",
    billing: {activePlanId: "growth", subscriptionStatus: "active",
      usedJobPosts: 2, directDebitMandateId: "secret"},
  }, filters, new Map());
  assert.equal(entry.data.planId, "growth");
  assert.equal(entry.data.usedJobPosts, 2);
  assert.equal(entry.data.billing, undefined);
  assert.equal(entry.data.directDebitMandateId, undefined);
  assert.ok(filterDirectoryRecord("employer-1", {
    role: "employer", billing: {activePlanId: "growth"},
  }, {...filters, plan: "growth"}, new Map()));
  assert.equal(filterDirectoryRecord("employer-1", {
    role: "employer", billing: {activePlanId: "growth"},
  }, {...filters, plan: "starter"}, new Map()), null);
});

test("full names and formatted phone numbers match directory search", () => {
  const filters = {role: "worker", search: "Alex Taylor", status: "all",
    professionTerms: [], location: "", origin: null};
  const data = {firstName: "Alex", lastName: "Taylor", phone: "+44 7700 900123"};
  assert.ok(filterDirectoryRecord("worker-1", data, filters, new Map()));
  filters.search = "7700900123";
  assert.ok(filterDirectoryRecord("worker-1", data, filters, new Map()));
});

test("broadcast audiences are isolated and delivery IDs are stable", () => {
  assert.equal(matchesBroadcastAudience("worker", {role: "worker"}), true);
  assert.equal(matchesBroadcastAudience("worker", {role: "employer"}), false);
  assert.equal(matchesBroadcastAudience("employer", {role: "company"}), true);
  assert.equal(matchesBroadcastAudience("all", {role: "admin"}), false);
  assert.equal(matchesBroadcastAudience("all", {role: "worker", deleted: true}), false);
  assert.equal(broadcastTargetId("campaign-1", "worker-1"),
    broadcastTargetId("campaign-1", "worker-1"));
  assert.notEqual(broadcastTargetId("campaign-1", "worker-1"),
    broadcastTargetId("campaign-1", "worker-2"));
});
