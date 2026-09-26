const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SUCCESSFUL_PAYMENT_STATUSES,
  PENDING_PAYMENT_STATUSES,
  nextScheduledCharge,
  latestConfirmedPayment,
} = require("../gocardless_state");

test("only confirmed and paid out payments complete billing", () => {
  assert.equal(SUCCESSFUL_PAYMENT_STATUSES.has("confirmed"), true);
  assert.equal(SUCCESSFUL_PAYMENT_STATUSES.has("paid_out"), true);
  assert.equal(SUCCESSFUL_PAYMENT_STATUSES.has("submitted"), false);
  assert.equal(PENDING_PAYMENT_STATUSES.has("submitted"), true);
});

test("next charge uses provider schedule after successful charge", () => {
  const subscription = {upcoming_payments: [
    {charge_date: "2026-09-01"},
    {charge_date: "2026-10-01"},
    {charge_date: "2026-11-02"},
  ]};
  assert.equal(nextScheduledCharge(subscription, "2026-09-01"), "2026-10-01");
  assert.equal(nextScheduledCharge(subscription, "2026-11-02"), null);
});

test("replayed payment does not displace latest confirmed payment", () => {
  const payments = [
    {id: "old", status: "confirmed", charge_date: "2026-08-01"},
    {id: "new", status: "paid_out", charge_date: "2026-09-01"},
    {id: "pending", status: "submitted", charge_date: "2026-10-01"},
  ];
  assert.equal(latestConfirmedPayment(payments).id, "new");
});
