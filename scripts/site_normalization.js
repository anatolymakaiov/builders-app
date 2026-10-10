"use strict";

const crypto = require("node:crypto");

const text = (value) => String(value || "").trim();
const normal = (value) => text(value).toLowerCase().replace(/\s+/g, " ");
const postcodeKey = (value) => normal(value).replace(/\s/g, "");

function vacancySite(job) {
  const owners = [job.ownerId, job.employerId].map(text).filter(Boolean);
  if (new Set(owners).size !== 1) return null;
  const ownerId = owners[0];
  const name = text(job.site || job.siteName);
  const addressLine1 = text(job.siteAddressLine1 || job.addressLine1 || job.street);
  const city = text(job.siteCity || job.city);
  const postcode = text(job.sitePostcode || job.postcode);
  if (normal(name).length < 4 ||
      ["site", "project", "construction site", "main site"].includes(normal(name)) ||
      !addressLine1 || !city || !/^[a-z]{1,2}\d[a-z\d]?\s*\d[a-z]{2}$/i.test(postcode)) {
    return null;
  }
  return {ownerId, name, addressLine1, city, postcode,
    region: text(job.siteCounty || job.county || job.region),
    country: text(job.siteCountry || job.country) || "United Kingdom"};
}

function siteIdentity(site) {
  return [site.ownerId, site.name, site.addressLine1, site.postcode]
    .map(normal).join("|");
}

function deterministicSiteId(site) {
  return `vacancy_${crypto.createHash("sha256").update(siteIdentity(site)).digest("hex")}`;
}

function sameSite(a, b) {
  return normal(a.name) === normal(b.name) &&
    normal(a.addressLine1) === normal(b.addressLine1) &&
    postcodeKey(a.postcode) === postcodeKey(b.postcode) &&
    normal(a.city) === normal(b.city);
}

function matchSite(candidate, sites) {
  const sameLocation = sites.filter((site) =>
    site.ownerId === candidate.ownerId &&
    postcodeKey(site.postcode) === postcodeKey(candidate.postcode) &&
    (normal(site.name) === normal(candidate.name) ||
      normal(site.addressLine1) === normal(candidate.addressLine1)));
  if (sameLocation.length === 0) return {kind: "create"};
  const exact = sameLocation.filter((site) => sameSite(site, candidate));
  return exact.length === 1 && sameLocation.length === 1 ?
    {kind: "link", id: exact[0].id} : {kind: "ambiguous"};
}

module.exports = {normal, postcodeKey, vacancySite, siteIdentity,
  deterministicSiteId, sameSite, matchSite};
