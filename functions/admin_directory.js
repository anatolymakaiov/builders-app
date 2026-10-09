function normalized(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

function profileText(data) {
  return normalized([
    data.name, data.displayName, data.firstName, data.lastName,
    data.companyName, data.businessName, data.email, data.phone,
    data.phoneNumber, data.postcode, data.city, data.townCity,
  ].join(" "));
}

function locationText(data) {
  return normalized([data.location, data.address, data.city, data.townCity,
    data.town, data.county, data.postcode, data.postCode]
      .join(" "));
}

function matchesProfession(data, terms) {
  if (!terms.length) return true;
  const values = [data.trade, data.position, data.registrationPosition,
    data.profession, ...(Array.isArray(data.trades) ? data.trades : [])]
      .map(normalized).filter(Boolean);
  return values.some((value) => terms.some((term) => {
    const match = normalized(term);
    return match && (value === match || value.includes(match));
  }));
}

function distanceKm(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) *
      Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.min(1, Math.sqrt(h)));
}

function broadcastTargetId(campaignId, uid) {
  return `${campaignId}_${uid}`;
}

function matchesBroadcastAudience(audience, profile) {
  const role = String(profile.role || "").toLowerCase();
  if (profile.deleted === true || profile.accountDeleted === true) return false;
  if (audience === "all") return ["worker", "employer", "company"].includes(role);
  if (audience === "employer") return role === "employer" || role === "company";
  return audience === "worker" && role === "worker";
}

function profileCoordinates(data, postcodeCoordinates) {
  const lat = Number(data.lat ?? data.latitude);
  const lng = Number(data.lng ?? data.longitude);
  if (Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0) {
    return {lat, lng};
  }
  return postcodeCoordinates.get(normalized(data.postcode || data.postCode)) || null;
}

function filterDirectoryRecord(id, data, filters, postcodeCoordinates) {
  if (filters.search && !`${normalized(id)} ${profileText(data)}`.includes(normalized(filters.search))) {
    return null;
  }
  if (filters.role === "worker" && !matchesProfession(data, filters.professionTerms)) {
    return null;
  }
  if (filters.role === "employer" && filters.plan && filters.plan !== "all") {
    const billing = data.billing || {};
    const plan = String(billing.activePlanId || billing.planId || "").toLowerCase();
    if (plan !== filters.plan) return null;
  }
  if (filters.status === "active" &&
      (data.active === false || data.deleted === true || data.accountDeleted === true ||
      data.moderationHold === true || data.profileSuspended === true ||
      data.profileHold === true || data.accountOnHold === true ||
      ["suspended", "on_hold"].includes(data.status))) return null;
  if (filters.status === "blocked" &&
      !(data.moderationHold === true || data.profileSuspended === true ||
      data.profileHold === true || data.accountOnHold === true ||
      ["suspended", "on_hold"].includes(data.status))) return null;
  let distance = null;
  if (filters.origin) {
    const coords = profileCoordinates(data, postcodeCoordinates);
    if (!coords) return null;
    distance = distanceKm(filters.origin, coords);
    if (distance > filters.radiusKm) return null;
  } else if (filters.location && !locationText(data).includes(normalized(filters.location))) {
    return null;
  }
  const summaryFields = ["role", "name", "displayName", "firstName", "lastName",
    "companyName", "businessName",
    "trade", "position", "registrationPosition", "profession", "trades",
    "location", "city", "townCity", "postcode", "postCode", "active",
    "deleted", "accountDeleted", "moderationHold", "profileSuspended",
    "profileHold", "accountOnHold", "status", "photo", "avatarUrl",
    "photoUrl", "profilePhotoUrl", "companyLogo", "companyLogoUrl",
    "companyAvatarUrl", "logo", "employerAvatarUrl", "createdAt",
    "availabilityStatus", "effectiveAvailabilityStatus", "ratingAverage",
    "ratingCount", "reviewCount", "averageRating", "totalReviews",
    "availableFrom"];
  const summary = Object.fromEntries(summaryFields
    .filter((field) => data[field] != null)
    .map((field) => [field, data[field]]));
  if (filters.role === "employer") {
    const billing = data.billing || {};
    summary.planId = billing.activePlanId || billing.planId || "";
    summary.subscriptionStatus = billing.subscriptionStatus || "";
    summary.usedJobPosts = billing.usedJobPosts ?? 0;
  }
  return {id, data: summary, distanceKm: distance};
}

module.exports = {normalized, matchesProfession, distanceKm, filterDirectoryRecord,
  broadcastTargetId, matchesBroadcastAudience};
