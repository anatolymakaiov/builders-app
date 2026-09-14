# Profile / Team Parity Audit

Scope: profile pages, profile services, new team/report/communication adapters.
No mobile presentation imports or shared/backend edits. No commit/push.

## Capability Matrix Before Implementation

| Capability / role | Mobile source and behavior | Backend | Initial web status |
|---|---|---|---|
| Worker identity / all viewers | worker_profile_screen: name, photo, profileHeaderImage/headerImage | users | Partial: generic name/avatar precedence |
| Company identity / all viewers | employer_profile_screen: companyName, photo, bio | users | Partial: generic fields can override company |
| Held profiles / owner vs external | ModerationHoldService: four hold flags and suspended/on_hold; external unavailable, owner suspension notice | users | Missing |
| Worker CV | About, experience years/months and details, permits, qualifications, certifications, education, previousWork, references | users | Partial |
| Worker portfolio | worker_profile_screen, portfolio_screen: nested and userId-constrained flat images | users/{id}/portfolio, portfolio | Partial: wrong url key, missing flat reads |
| Worker portfolio management / owner | portfolio_screen: upload, delete | Storage portfolio, both portfolio collections | Partial |
| Company content | company_profile_sections: goals, advantages, clients, who we are, history | company-prefixed users fields | Missing |
| Contacts | worker/employer profiles: phone, phones, contactPerson, email, website, contacts | users | Partial |
| Company vacancies | employer_profile_screen | constrained jobs query | Partial: list without navigation |
| Profile edit / owner | edit_profile_screen, verification, CV, company fields | users, verification services | Partial |
| Team discovery | worker profile: members and ownerId | teams | Partial: unrestricted collection read |
| Create team / worker | nonempty name, owner-scoped duplicate check, hold guard | teams; nameLower, memberKey, memberStatuses | Partial: noncanonical extra membership fields |
| Team read / members | team_details: actual members, ownerId or createdBy leader | teams, users | Partial: stale aliases resurrect members |
| Team edit / leader | description, avatar, background, portfolio upload | teams + portfolio + Storage | Partial: any own-profile team editable |
| Add member / leader | exact phone/nickname/nickName/username lookup; worker only; duplicate check | users, teams.members/memberStatuses | Missing |
| Remove member / leader | cannot remove self; confirmation; fresh membership | teams | Missing |
| Leave team / nonleader member | confirmation; leader must delete | teams | Missing |
| Delete team / leader | confirmation; delete portfolio docs + team, preserve applications/chats | teams | Missing |
| Team communication | internal member chat, employer team chat, phone fallback to leader | ChatService, chats | Missing |
| Worker reviews / employers | worker_profile_screen: any employer viewing another worker, rating 1-5, optional comment/job; no duplicate check | users/{worker}/reviews | Missing |
| Review aggregate | mobile attempts rating/reviewsCount write on worker | users | Blocked by owner-only users update rule |
| Legacy job reviews | review_worker_screen: jobId/rating/review; no eligibility or duplicate guard | reviews | Missing; separate job-context flow |
| Direct communication | ProfileCommunicationService: reuse participant chats, role-specific creation | chats, neutral ChatService | Missing |
| Reports / other profile | ReportService: worker/employer types; report/admin inbox/thread atomic linkage | reports, admin_messages, message_threads | Missing |
| Team invitations/status/availability | No invitation acceptance/decline UI or generic member-status editor in team_details; application participation belongs to applications workflow | applications | Not a standalone team capability |

## Implementation results

The safe gaps above are implemented through `web_profile_page.dart`,
`web_team_page.dart`, `web_worker_reviews.dart`, and their Web-only services.
This includes held/unavailable handling, legacy profile/portfolio resolution,
expanded Worker and company information, profile media editing, direct
communication, reports, team creation/management/media/contact actions, and
reviews. The consolidated status and the explicit remaining editor/backend gaps
are recorded in `business_parity_matrix.md`.
