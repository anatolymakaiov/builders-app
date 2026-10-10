"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {vacancySite, deterministicSiteId, matchSite} =
  require("../../scripts/site_normalization");

const vacancy = {ownerId: "employer-a", employerId: "employer-a",
  site: "Manchester Tower", street: "10 Main Street",
  city: "Manchester", postcode: "M1 1AE"};

test("legacy vacancy matches only a strong exact Site in its employer context", () => {
  const candidate = vacancySite(vacancy);
  assert.ok(candidate);
  const own = {...candidate, id: "site-a"};
  assert.deepEqual(matchSite(candidate, [own]), {kind: "link", id: "site-a"});
  assert.equal(matchSite(candidate, [{...own, name: "Manchester Tower Phase 2"}]).kind,
    "ambiguous");
  assert.equal(matchSite(candidate, [{...own, name: "Manchester Tower Phase 2",
    addressLine1: "12 Main Street"}]).kind, "create");
  assert.equal(matchSite(candidate, [{...own, addressLine1: "12 Main Street"}]).kind,
    "ambiguous");
  assert.equal(matchSite(candidate, [{...own, name: "Renamed Tower"}]).kind,
    "ambiguous");
  assert.equal(matchSite(candidate, [own, {...own, id: "duplicate"}]).kind,
    "ambiguous");
  assert.equal(matchSite(candidate, [{...own, ownerId: "employer-b"}]).kind,
    "create");
});

test("identity is deterministic and owner-specific, with no vague creation", () => {
  const candidate = vacancySite(vacancy);
  assert.equal(deterministicSiteId(candidate), deterministicSiteId(vacancySite(vacancy)));
  assert.notEqual(deterministicSiteId(candidate),
    deterministicSiteId(vacancySite({...vacancy, ownerId: "employer-b",
      employerId: "employer-b"})));
  assert.equal(vacancySite({...vacancy, employerId: "employer-b"}), null);
  assert.equal(vacancySite({...vacancy, site: "Site"}), null);
  assert.equal(vacancySite({...vacancy, street: ""}), null);
});
