#!/usr/bin/env node
"use strict";

const path = require("node:path");
const {createRequire} = require("node:module");
const admin = createRequire(path.join(__dirname, "../functions/package.json"))("firebase-admin");
const {vacancySite, normal, postcodeKey, deterministicSiteId, sameSite,
  matchSite} = require("./site_normalization");

const commit = process.argv.includes("--commit");
const allowedJobIds = new Set((process.argv.find((arg) =>
  arg.startsWith("--allow-create=")) || "").replace("--allow-create=", "")
  .split(",").filter(Boolean));
admin.initializeApp({projectId: "builder-jobs-app"});
const db = admin.firestore();
const summary = {scanned: 0, alreadyLinked: 0, linkedExisting: 0,
  linkedNew: 0, newSitesCreated: 0, wouldCreateSites: 0,
  reviewRequired: 0, ambiguous: 0, skipped: 0, errors: 0};

async function scanJobs() {
  const jobs = [];
  let last = null;
  do {
    let query = db.collection("jobs").orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (last) query = query.startAfter(last);
    const snapshot = await query.get();
    jobs.push(...snapshot.docs);
    last = snapshot.size === 200 ? snapshot.docs.at(-1) : null;
  } while (last);
  return jobs;
}

async function employerSites(ownerId) {
  const snapshot = await db.collection("sites")
    .where("employerContextId", "==", ownerId).get();
  return snapshot.docs.map((doc) => ({id: doc.id, ownerId,
    name: doc.get("name"), addressLine1: doc.get("addressLine1"),
    city: doc.get("city"), postcode: doc.get("postcode")}));
}

async function linkJob(job, candidate, siteId) {
  if (!commit) return true;
  return db.runTransaction(async (tx) => {
    const current = await tx.get(job.ref);
    if (!current.exists || current.get("siteId")) return false;
    const latest = vacancySite(current.data());
    if (!latest || latest.ownerId !== candidate.ownerId ||
        !sameSite(latest, candidate)) return false;
    tx.update(job.ref, {siteId});
    return true;
  });
}

async function ensureSite(candidate) {
  const id = deterministicSiteId(candidate);
  const ref = db.collection("sites").doc(id);
  if (!commit) return id;
  await db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (current.exists) {
      const data = current.data();
      if (data.employerContextId !== candidate.ownerId ||
          !sameSite({ownerId: data.employerContextId,
            name: data.name, addressLine1: data.addressLine1,
            city: data.city, postcode: data.postcode}, candidate)) {
        throw Error("Deterministic Site ID conflict");
      }
      return;
    }
    tx.create(ref, {siteId: id, employerContextId: candidate.ownerId,
      ownerUid: candidate.ownerId, name: candidate.name, status: "active",
      addressLine1: candidate.addressLine1, addressLine2: "",
      city: candidate.city, region: candidate.region,
      postcode: candidate.postcode, country: candidate.country,
      description: "", createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
  return id;
}

async function main() {
  const jobs = await scanJobs();
  summary.scanned = jobs.length;
  const candidates = [];
  const addresses = new Map();
  for (const doc of jobs) {
    const data = doc.data();
    if (data.siteId) {summary.alreadyLinked++; continue;}
    const site = vacancySite(data);
    if (!site) {summary.skipped++; continue;}
    candidates.push({doc, site});
    const key = [site.ownerId, site.name, postcodeKey(site.postcode)]
      .map(normal).join("|");
    if (!addresses.has(key)) addresses.set(key, new Set());
    addresses.get(key).add(`${normal(site.addressLine1)}|${normal(site.city)}`);
  }
  const sitesByOwner = new Map();
  const validOwner = new Map();
  const createdIds = new Set();
  const reviewedIds = new Set(candidates
    .filter(({doc}) => allowedJobIds.has(doc.id))
    .map(({site}) => deterministicSiteId(site)));
  for (const {doc, site} of candidates) {
    const key = [site.ownerId, site.name, postcodeKey(site.postcode)].map(normal).join("|");
    if (addresses.get(key).size > 1) {summary.ambiguous++; continue;}
    if (!validOwner.has(site.ownerId)) {
      const owner = await db.collection("users").doc(site.ownerId).get();
      validOwner.set(site.ownerId, owner.exists &&
        ["employer", "company"].includes(owner.get("role")));
    }
    if (!validOwner.get(site.ownerId)) {summary.skipped++; continue;}
    if (!sitesByOwner.has(site.ownerId)) {
      sitesByOwner.set(site.ownerId, await employerSites(site.ownerId));
    }
    const known = sitesByOwner.get(site.ownerId);
    const match = matchSite(site, known);
    if (match.kind === "ambiguous") {summary.ambiguous++; continue;}
    try {
      let id = match.id;
      if (match.kind === "create") {
        id = deterministicSiteId(site);
        if (commit && !reviewedIds.has(id)) {
          summary.reviewRequired++;
          continue;
        }
        if (!createdIds.has(id)) {
          await ensureSite(site);
          createdIds.add(id);
          if (commit) summary.newSitesCreated++;
          else summary.wouldCreateSites++;
          known.push({...site, id});
        }
      }
      if (!await linkJob(doc, site, id)) {
        summary.skipped++;
        continue;
      }
      if (createdIds.has(id)) summary.linkedNew++;
      else summary.linkedExisting++;
    } catch (_) {
      summary.errors++;
    }
  }
  console.log(JSON.stringify({mode: commit ? "commit" : "dry-run", ...summary}));
  if (summary.errors) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
