"use strict";

function normalizedMemberIds(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(String).filter(Boolean))];
}

function selectAuthorizedAccountLinkGroup(sourceUid, targetUid, groups) {
  const matches = groups.filter((group) => {
    if (!group.exists || !group.groupId) return false;
    const members = normalizedMemberIds(group.memberIds);
    return members.includes(sourceUid) && members.includes(targetUid);
  });
  if (matches.length === 1) return matches[0].groupId;
  if (matches.length > 1) return "ambiguous";
  return null;
}

module.exports = {
  normalizedMemberIds,
  selectAuthorizedAccountLinkGroup,
};
