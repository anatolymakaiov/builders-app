function isOpenForHiring(job) {
  const status = String(job.status || "active").trim().toLowerCase();
  const positions = Number(job.positions) > 0 ? Number(job.positions) : 1;
  const filled = Number(job.filledPositions ??
    job.acceptedSlotTotal ?? job.hiredCount ?? job.acceptedCount) || 0;
  return job.moderationStatus === "approved" &&
    ["active", "published", "open"].includes(status) &&
    job.deleted !== true && job.isDeleted !== true &&
    job.active !== false && job.isActive !== false &&
    job.billingSuspended !== true &&
    job.employerDeleted !== true && job.companyDeleted !== true &&
    Math.max(positions - filled, 0) > 0;
}

module.exports = {isOpenForHiring};
