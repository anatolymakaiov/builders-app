const assert = require("node:assert/strict");
const test = require("node:test");
const {report, periodKeys, completeUser, acceptedWorkerCount} =
  require("../admin_analytics");

const now = new Date("2026-09-28T12:00:00Z");

test("calendar buckets follow month and year boundaries", () => {
  assert.equal(periodKeys("month", now).length, 30);
  assert.equal(periodKeys("year", now).length, 12);
  assert.equal(periodKeys("month", now)[0], "2026-09-01");
});

test("only confirmed GBP revenue is counted and refunds reduce collected amount", () => {
  const result = report({tab: "revenue", period: "month", now, payments: [
    {currency: "GBP", status: "confirmed", amount: 4900,
      amount_refunded: 900, charge_date: "2026-09-10", links: {mandate: "MD1"}},
    {currency: "GBP", status: "failed", amount: 9900,
      charge_date: "2026-09-11", links: {mandate: "MD1"}},
    {currency: "GBP", status: "submitted", amount: 9900,
      charge_date: "2026-09-30", links: {mandate: "MD1"}},
  ]});
  assert.equal(result.kpis["Confirmed revenue"], 4000);
  assert.equal(result.kpis["Scheduled Direct Debit"], 9900);
});

test("retention uses mature first-payment customer cohorts", () => {
  const result = report({tab: "revenue", period: "year", now, payments: [
    {currency: "GBP", status: "confirmed", amount: 4900,
      charge_date: "2026-01-01", analyticsCustomerId: "CU1"},
    {currency: "GBP", status: "confirmed", amount: 4900,
      charge_date: "2026-02-01", analyticsCustomerId: "CU1"},
    {currency: "GBP", status: "confirmed", amount: 9900,
      charge_date: "2026-03-01", analyticsCustomerId: "CU2"},
    {currency: "GBP", status: "confirmed", amount: 19900,
      charge_date: "2026-09-20", analyticsCustomerId: "CU3"},
  ]});
  assert.equal(result.kpis["First-payment cohort"], 2);
  assert.equal(result.kpis["Second successful payment"], 1);
  assert.equal(result.kpis["Retention percent"], 50);
  assert.equal(result.kpis["Drop-off percent"], 50);
});

test("retention is unavailable when mandate-to-customer links are incomplete", () => {
  const result = report({tab: "revenue", period: "year", now,
    payments: [{currency: "GBP", status: "confirmed", amount: 4900,
      charge_date: "2026-01-01"}], retentionComplete: false});
  assert.equal(result.kpis["Retention percent"], null);
  assert.equal(result.kpis["First-payment cohort"], null);
  assert.equal(result.kpis["Confirmed revenue"], 4900);
});

test("hires count accepted team workers, not sent offers", () => {
  const result = report({tab: "hires", period: "month", now, applications: [
    {status: "offer_accepted", slotDecrementApplied: true,
      slotDecrementAppliedAt: new Date("2026-09-10T12:00:00Z"),
      offer: {selectedWorkerIds: ["A", "B"]}},
    {status: "offer_sent", slotDecrementApplied: false,
      slotDecrementAppliedAt: new Date("2026-09-10T12:00:00Z")},
  ]});
  assert.equal(result.kpis["Completed hires"], 2);
  assert.equal(acceptedWorkerCount({workersCount: 3}), 3);
});

test("vacancy closures use lifecycle events rather than current updatedAt", () => {
  const result = report({tab: "vacancies", period: "month", now,
    jobs: [
      {status: "active", moderationStatus: "approved",
        createdAt: new Date("2026-09-03T12:00:00Z")},
      {status: "closed", moderationStatus: "approved",
        createdAt: new Date("2026-09-02T12:00:00Z"),
        updatedAt: new Date("2026-09-22T12:00:00Z")},
    ],
    closures: [{closedAt: new Date("2026-09-20T12:00:00Z")}],
  });
  assert.equal(result.kpis["Created vacancies"], 2);
  assert.equal(result.kpis["Tracked closures"], 1);
  assert.equal(result.kpis["Current active vacancies"], 1);
});

test("incomplete users and oversized reports are not presented as complete", () => {
  assert.equal(completeUser({role: "worker", name: "A", profileComplete: false}), false);
  assert.equal(completeUser({role: "employer", companyName: "Co"}), true);
  const result = report({tab: "users", period: "month", now,
    users: [{role: "worker", name: "A"}], complete: false});
  assert.deepEqual(result.kpis, {});
  assert.equal(result.notes.length, 1);
});
