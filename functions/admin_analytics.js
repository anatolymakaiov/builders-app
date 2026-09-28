const {SUCCESSFUL_PAYMENT_STATUSES, PENDING_PAYMENT_STATUSES} =
  require("./gocardless_state");

const londonDay = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/London", year: "numeric", month: "2-digit", day: "2-digit",
});

function dateKey(value) {
  if (!value) return "";
  const date = value.toDate ? value.toDate() : new Date(value);
  return Number.isNaN(date.getTime()) ? "" : londonDay.format(date);
}

function monthKey(value) {
  return dateKey(value).slice(0, 7);
}

function periodKeys(period, now = new Date()) {
  const today = dateKey(now);
  const year = Number(today.slice(0, 4));
  const month = Number(today.slice(5, 7));
  if (period === "year") {
    return Array.from({length: 12}, (_, index) =>
      `${year}-${String(index + 1).padStart(2, "0")}`);
  }
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return Array.from({length: days}, (_, index) =>
    `${year}-${String(month).padStart(2, "0")}-${String(index + 1).padStart(2, "0")}`);
}

function groupValues(records, keys, period, dateOf, valueOf = () => 1) {
  const totals = Object.fromEntries(keys.map((key) => [key, 0]));
  for (const record of records) {
    const key = period === "year" ? monthKey(dateOf(record)) : dateKey(dateOf(record));
    if (Object.hasOwn(totals, key)) totals[key] += valueOf(record);
  }
  return keys.map((key) => totals[key]);
}

function completeUser(user) {
  if (!user || user.deleted === true || user.accountDeleted === true ||
      user.anonymised === true || user.active === false ||
      user.profileSuspended === true || user.moderationHold === true) return false;
  if (["profileComplete", "onboardingComplete", "profileCreated"]
    .some((field) => user[field] === true)) return true;
  if (["profileComplete", "onboardingComplete", "profileCreated"]
    .some((field) => Object.hasOwn(user, field))) return false;
  if (user.draft === true || user.pendingRegistration === true ||
      user.registrationFormComplete === false) return false;
  return user.role === "employer" ? !!String(user.companyName || "").trim() :
    !!String(user.name || "").trim();
}

function acceptedWorkerCount(application) {
  const selected = application.offer && application.offer.selectedWorkerIds;
  if (Array.isArray(selected) && selected.length) {
    return new Set(selected.map(String)).size;
  }
  if (Number(application.workersCount) > 0) return Number(application.workersCount);
  if (Array.isArray(application.members) && application.members.length) {
    return new Set(application.members.map(String)).size;
  }
  return 1;
}

function report({tab, period, now = new Date(), payments = [], users = [], jobs = [],
  applications = [], closures = [], complete = true, retentionComplete = true}) {
  const keys = periodKeys(period, now);
  const data = {keys, series: {}, kpis: {}, notes: []};
  if (!complete) {
    data.notes.push("The source exceeded the safe report limit. Metrics are unavailable rather than partial.");
    return data;
  }
  if (tab === "revenue") {
    const confirmed = payments.filter((payment) =>
      payment.currency === "GBP" && SUCCESSFUL_PAYMENT_STATUSES.has(payment.status));
    const scheduled = payments.filter((payment) =>
      payment.currency === "GBP" && PENDING_PAYMENT_STATUSES.has(payment.status) &&
      payment.charge_date >= dateKey(now));
    data.series.Confirmed = groupValues(confirmed, keys, period,
      (payment) => payment.charge_date, (payment) => Math.max(0,
        Number(payment.amount || 0) - Number(payment.amount_refunded || 0)));
    data.series.Scheduled = groupValues(scheduled, keys, period,
      (payment) => payment.charge_date, (payment) => Number(payment.amount || 0));
    data.kpis["Confirmed revenue"] = data.series.Confirmed.reduce((a, b) => a + b, 0);
    data.kpis["Scheduled Direct Debit"] = data.series.Scheduled.reduce((a, b) => a + b, 0);
    const byCustomer = new Map();
    for (const payment of confirmed) {
      const id = payment.analyticsCustomerId;
      if (!id) continue;
      if (!byCustomer.has(id)) byCustomer.set(id, []);
      byCustomer.get(id).push(payment);
    }
    const mature = [];
    for (const history of byCustomer.values()) {
      history.sort((a, b) => a.charge_date.localeCompare(b.charge_date));
      const first = history[0];
      const age = (now - new Date(`${first.charge_date}T12:00:00Z`)) / 86400000;
      if (age < 60) continue;
      const key = period === "year" ? first.charge_date.slice(0, 7) : first.charge_date;
      if (keys.includes(key)) mature.push(history);
    }
    data.kpis["First-payment cohort"] = retentionComplete ? mature.length : null;
    data.kpis["Second successful payment"] = retentionComplete ? mature.filter((history) =>
      history.length > 1 &&
      (new Date(`${history[1].charge_date}T12:00:00Z`) -
       new Date(`${history[0].charge_date}T12:00:00Z`)) / 86400000 <= 60).length : null;
    data.kpis["Retention percent"] = retentionComplete && mature.length
      ? Math.round(100 * data.kpis["Second successful payment"] / mature.length) : null;
    data.kpis["Drop-off percent"] = retentionComplete && mature.length
      ? 100 - data.kpis["Retention percent"] : null;
    data.notes.push("Cohort: GoCardless customers with a first confirmed GBP payment in this period and at least 60 days of follow-up. Retained means a second confirmed payment within 60 days. The metric is unavailable if mandate-to-customer history is incomplete.");
  } else if (tab === "vacancies") {
    data.series.Created = groupValues(jobs, keys, period, (job) => job.createdAt);
    data.series.Closed = groupValues(closures, keys, period,
      (event) => event.closedAt);
    data.kpis["Created vacancies"] = data.series.Created.reduce((a, b) => a + b, 0);
    data.kpis["Tracked closures"] = data.series.Closed.reduce((a, b) => a + b, 0);
    data.kpis["Current active vacancies"] = jobs.filter((job) =>
      job.moderationStatus === "approved" &&
      ["active", "published", "open"].includes(job.status) &&
      job.active !== false && job.deleted !== true && job.isDeleted !== true).length;
    data.notes.push("Closures count approved live vacancies transitioning to closed, inactive or deactivated. Tracking starts with this Admin release; older closures have no reliable timestamp and are not backfilled.");
  } else if (tab === "hires") {
    const accepted = applications.filter((application) =>
      ["offer_accepted", "accepted", "hired"].includes(application.status) &&
      application.slotDecrementApplied === true);
    data.series.Hires = groupValues(accepted, keys, period,
      (application) => application.slotDecrementAppliedAt,
      acceptedWorkerCount);
    data.kpis["Completed hires"] = data.series.Hires.reduce((a, b) => a + b, 0);
    data.notes.push("Completed hire: accepted offer with slot decrement applied. Team offers count selected accepted workers. Legacy acceptances without a timestamp are excluded.");
  } else if (tab === "users") {
    const workers = users.filter((user) => user.role === "worker" && completeUser(user));
    const employers = users.filter((user) => user.role === "employer" && completeUser(user));
    data.series.Workers = groupValues(workers, keys, period, (user) => user.createdAt);
    data.series.Employers = groupValues(employers, keys, period, (user) => user.createdAt);
    data.kpis["Current workers"] = workers.length;
    data.kpis["Current employers"] = employers.length;
    data.notes.push("Completed, active profile documents only; registration date uses createdAt.");
  }
  return data;
}

module.exports = {report, periodKeys, completeUser, acceptedWorkerCount};
