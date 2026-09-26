const SUCCESSFUL_PAYMENT_STATUSES = new Set(["confirmed", "paid_out"]);
const PENDING_PAYMENT_STATUSES = new Set(["pending_submission", "submitted"]);

function nextScheduledCharge(subscription, afterDate = "") {
  const dates = (subscription.upcoming_payments || [])
    .map((payment) => payment && payment.charge_date)
    .filter((date) => /^\d{4}-\d{2}-\d{2}$/.test(date) && date > afterDate)
    .sort();
  return dates[0] || null;
}

function latestConfirmedPayment(payments) {
  return (payments || [])
    .filter((payment) => SUCCESSFUL_PAYMENT_STATUSES.has(payment.status))
    .sort((a, b) => String(b.charge_date || b.created_at || "")
      .localeCompare(String(a.charge_date || a.created_at || "")))[0] || null;
}

module.exports = {
  SUCCESSFUL_PAYMENT_STATUSES,
  PENDING_PAYMENT_STATUSES,
  nextScheduledCharge,
  latestConfirmedPayment,
};
