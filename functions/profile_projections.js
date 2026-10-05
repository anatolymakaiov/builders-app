"use strict";

const text = (value, max = 120) => typeof value === "string"
  ? value.trim().slice(0, max) : "";

const first = (data, keys, max) => {
  for (const key of keys) {
    const value = text(data[key], max);
    if (value) return value;
  }
  return "";
};

const safeUrl = (value) => {
  const url = text(value, 2048);
  return /^https:\/\//i.test(url) ? url : "";
};

const safeMedia = (raw) => Array.isArray(raw)
  ? raw.map(safeUrl).filter(Boolean).slice(0, 30) : [];

const safeDate = (value) => {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? value : null;
  }
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const date = new Date(`${value}T00:00:00.000Z`);
    return !Number.isNaN(date.getTime()) &&
      date.toISOString().startsWith(value) ? value : null;
  }
  return null;
};

const isCompleted = (data) => {
  if (data.profileComplete === true || data.onboardingComplete === true ||
      data.profileCreated === true) return true;
  if (["profileComplete", "onboardingComplete", "profileCreated"]
    .some((key) => Object.hasOwn(data, key))) return false;
  if (data.draft === true || data.pendingRegistration === true ||
      data.registrationFormComplete === false) return false;
  return text(data.role).toLowerCase() === "employer"
    ? Boolean(first(data, ["companyName"], 120))
    : Boolean(first(data, ["name"], 120));
};

const isActive = (data) => data.active !== false && data.deleted !== true &&
  data.accountDeleted !== true && data.companyDeleted !== true &&
  data.anonymised !== true && data.moderationHold !== true &&
  data.profileSuspended !== true && data.profileHold !== true &&
  data.accountOnHold !== true &&
  !["deleted", "inactive", "suspended", "on_hold"].includes(
    text(data.status).toLowerCase());

const safeArea = (value) => {
  const area = text(value, 80);
  // A town or region is useful for discovery; digits/postcodes and address
  // punctuation indicate a street-level value and must never be projected.
  return area && !/[\d,@#\n]/.test(area) &&
    !/\b(street|road|lane|avenue|drive|close|court|flat|house|building)\b/i.test(area)
    ? area : "";
};

const safeName = (data) => {
  const full = first(data, ["name", "displayName", "registrationName"], 120);
  if (/[\d@]/.test(full)) return "";
  const parts = full.split(/\s+/).filter(Boolean);
  const given = first(data, ["firstName", "registrationFirstName"], 60) ||
    parts[0] || "";
  const family = first(data, ["lastName", "registrationLastName"], 60) ||
    parts.slice(1).join(" ");
  if (/[\d@]/.test(given) || /[\d@]/.test(family)) return "";
  return [given, family ? `${family[0].toUpperCase()}.` : ""]
    .filter(Boolean).join(" ");
};

const publicProfile = (uid, data) => {
  const role = text(data.role).toLowerCase();
  if (!["worker", "employer", "company"].includes(role) || !isCompleted(data)) {
    return null;
  }
  const employer = role !== "worker";
  const rawName = employer
    ? first(data, ["companyName", "businessName", "displayName", "name"], 120)
    : safeName(data);
  const name = /@|\d{7,}|\b(street|road|lane|avenue|drive|flat)\b/i
    .test(rawName) ? "" : rawName;
  const avatarUrl = safeUrl(first(data, employer
    ? ["companyLogoUrl", "companyLogo", "companyAvatarUrl", "avatarUrl", "photoUrl"]
    : ["avatarUrl", "photoUrl", "profilePhotoUrl", "photo"], 2048));
  const headerImageUrl = safeUrl(first(data, employer
    ? ["companyHeaderUrl", "profileHeaderImage", "headerImageUrl", "headerImage"]
    : ["profileHeaderImage", "headerImageUrl", "headerImage"], 2048));
  const availability = employer ? null : workerDiscovery(uid, data);
  return {
    uid,
    role: employer ? "employer" : "worker", // Display hint, never an authority.
    displayName: name || (employer ? "Company" : "Worker"),
    ...(employer ? {companyName: name || "Company"} : {name: name || "Worker"}),
    avatarUrl,
    photo: avatarUrl,
    headerImageUrl,
    profileHeaderImage: headerImageUrl,
    trade: employer ? "" : (/^[\p{L}\s&/()-]{1,80}$/u.test(first(data,
      ["trade", "position"], 120)) ? first(data, ["trade", "position"], 120) : ""),
    ...(employer ? {} : {
      experienceYears: Number.isFinite(Number(data.experienceYears))
        ? Math.min(Math.max(Math.floor(Number(data.experienceYears)), 0), 80) : 0,
      rating: Number.isFinite(Number(data.rating))
        ? Math.min(Math.max(Number(data.rating), 0), 5) : 0,
      availabilityStatus: availability.availabilityStatus,
      availableFrom: availability.availableFrom,
      allowVacancyInvites: data.allowVacancyInvites === true,
      availabilityConfirmedAt: safeDate(data.availabilityConfirmedAt),
    }),
    companyPhotos: employer ? safeMedia(data.companyPhotos) : [],
    portfolio: employer ? [] : safeMedia(data.portfolio),
    townCity: safeArea(first(data, ["townCity", "city", "town"], 80)),
    county: safeArea(data.county),
    active: isActive(data),
  };
};

const workerDiscovery = (uid, data) => {
  if (text(data.role).toLowerCase() !== "worker" || !isCompleted(data)) return null;
  const storedIds = Array.isArray(data.tradeIds) ? data.tradeIds : [];
  const tradeIds = [...new Set(storedIds.filter((id) =>
    typeof id === "string" && /^[a-z][a-z0-9_-]{1,63}$/.test(id)))].slice(0, 3);
  const primaryTradeId = tradeIds.includes(data.primaryTradeId)
    ? data.primaryTradeId : (tradeIds[0] || "");
  const confirmedAt = safeDate(data.availabilityConfirmedAt);
  const confirmed = confirmedAt != null;
  const rawStatus = text(data.availabilityStatus).toLowerCase();
  const availabilityStatus = confirmed &&
    ["available_now", "available_from", "busy", "not_looking"].includes(rawStatus)
    ? rawStatus : "unknown";
  const experience = Number(data.experienceYears);
  const rating = Number(data.rating);
  const ratingCount = Number(data.ratingCount ?? data.reviewCount);
  const active = isActive(data);
  return {
    workerId: uid,
    displayNameShort: safeName(data) || "Worker",
    avatarUrl: safeUrl(first(data,
      ["avatarUrl", "photoUrl", "profilePhotoUrl", "photo"], 2048)),
    primaryTradeId,
    tradeIds,
    experienceYears: Number.isFinite(experience) && experience >= 0
      ? Math.min(Math.floor(experience), 80) : 0,
    rating: Number.isFinite(rating) && rating >= 0
      ? Math.min(rating, 5) : 0,
    ratingCount: Number.isFinite(ratingCount) && ratingCount >= 0
      ? Math.floor(ratingCount) : 0,
    availabilityStatus,
    availableFrom: availabilityStatus === "available_from"
      ? safeDate(data.availableFrom) : null,
    allowVacancyInvites: data.allowVacancyInvites === true,
    availabilityConfirmedAt: confirmedAt,
    availabilityUpdatedAt: safeDate(data.availabilityUpdatedAt),
    generalArea: safeArea(first(data, ["townCity", "city", "town"], 80)),
    region: safeArea(data.county),
    profileCompleted: true,
    discoveryVisible: active && tradeIds.length > 0,
  };
};

module.exports = {publicProfile, workerDiscovery, safeArea};
