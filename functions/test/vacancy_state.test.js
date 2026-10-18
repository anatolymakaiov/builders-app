const assert = require("node:assert/strict");
const test = require("node:test");
const {isOpenForHiring} = require("../vacancy_state");

test("only approved live vacancies with remaining positions occupy a slot", () => {
  const base = {status: "active", moderationStatus: "approved", positions: 1};
  assert.equal(isOpenForHiring({...base, filledPositions: 0}), true);
  assert.equal(isOpenForHiring({...base, filledPositions: 1}), false);
  assert.equal(isOpenForHiring({...base, positions: 5, filledPositions: 3}), true);
  assert.equal(isOpenForHiring({...base, status: "closed"}), false);
  assert.equal(isOpenForHiring({...base, billingSuspended: true}), false);
});
