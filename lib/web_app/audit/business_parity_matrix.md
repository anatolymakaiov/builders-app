# STROYKA desktop Web business-parity audit

This audit compares the current mobile Worker and Employer business surfaces with
the separate desktop Web implementation rooted at `lib/main_web.dart`. The audit
was performed against the mobile screens, their directly used services/models,
and the Web shell/pages/services. No mobile presentation, Firebase rules,
functions, native configuration, or dependency files are changed by this work.

## Status definitions

- **COMPLETE**: the user can complete the mobile-equivalent business workflow on
  Web with the same persisted data contract.
- **PARTIAL**: the useful core workflow is present, but a named mobile edge or
  secondary control is absent.
- **DEFERRED**: intentionally not ported because it is native-only, not present in
  the current mobile workflow, or outside a safe Web-only implementation.
- **BLOCKED**: parity would require a backend/rules/schema change forbidden by
  this task.

## Parity matrix

| Area | Worker Web | Employer Web | Result and evidence |
| --- | --- | --- | --- |
| Jobs discovery | COMPLETE | COMPLETE | Polling data source; public/owner queries remain separate. Taxonomy text/role search, city/radius, hourly pay, format filters, newest/highest-pay/nearest sort, ten-item pagination, selected vacancy details, photos, company navigation. `web_jobs_page.dart`, `web_job_filters.dart`, `web_job_filters_dialog.dart`. |
| Saved jobs | COMPLETE | N/A | Reads/writes the existing `saved_jobs/{uid}/jobs` contract; all/saved toggle, immediate refresh, empty state. No parallel collection. |
| Apply | COMPLETE | N/A | Single application keeps the existing application schema and validation; team application calls the authoritative existing `submitTeamApplication` function after selecting an owned/member team. Held/deleted/inactive users and unavailable jobs are rejected before write. `web_apply_dialog.dart`, `web_jobs_data_service.dart`. |
| Employer vacancy management | N/A | COMPLETE | Existing Web create/edit/cancel/status flow retained; owner jobs include non-public states while public/map queries remain active-approved only. |
| Map | COMPLETE | COMPLETE | Desktop list/map split, clusters, geolocation, viewport movement, role filtering, selected vacancy details, save/apply/company actions. Zero results terminate loading. `web_map_page.dart`. |
| Applications list | COMPLETE | COMPLETE | Safe polling, status/search filters, newest activity ordering, Worker Single/Team separation, stable snapshot enrichment, unread/viewed updates and empty/error states. `web_applications_page.dart`, `web_applications_data_service.dart`. |
| Application details | COMPLETE | COMPLETE | Job/company/applicant/team snapshot, members, profile/chat actions and existing offer details/actions are retained. Team offers require selected members. Vacancy/company unavailable states use stored application data. |
| Offers | COMPLETE | COMPLETE | Existing shared offer acceptance service remains authoritative for slot decrement/idempotency. Web supports create, accept, reject, withdraw and selected team recipients without introducing a second offer model. |
| Chat list/thread | COMPLETE | COMPLETE | Stable get-based polling avoids Web Firestore snapshot lifecycle failures; list/thread loading always terminates. Latest 80 messages plus explicit older-message pagination, unread updates, typing, profile/job header navigation. `web_chats_page.dart`, `web_chats_data_service.dart`. |
| Chat message actions | COMPLETE | COMPLETE | Text, multi-attachment messages, preview/remove, image/video/audio/file display, voice recording, reply, copy, forward, edit, delete-for-me and delete-for-everyone use existing fields/storage contracts. |
| Worker profile | PARTIAL | COMPLETE viewer | Profile/header, expanded work history, permits, qualifications, education, references data, portfolio grid/viewer, contacts, teams, reviews, report/message/call and held/unavailable handling. Owner can edit core fields/media. See missing list for fine-grained reference editor parity. |
| Company profile | PARTIAL owner | COMPLETE viewer | Company identity, header/logo, overview fields, contacts, photos, jobs, message/report and held/unavailable handling. Owner edits core fields/media; company job cards remain summary-only in this profile surface. |
| Teams | COMPLETE | COMPLETE viewer | Create with duplicate-name compatibility fields; separate avatar/header; description, photos, member list/profile navigation, leader add/message/remove, regular-member leave, leader delete, stable return navigation, contact action. Existing application/chat history is preserved. `web_team_page.dart`, `web_team_actions.dart`. |
| Reviews | PARTIAL | COMPLETE create/view | Reviews are read from the existing worker review subcollection and average is derived; employers can create the same review record. Persisting the denormalized `users.rating/reviewsCount` aggregate is BLOCKED by current cross-user write rules, so Web does not attempt the mobile write that can be denied. |
| Notifications/alerts | COMPLETE | COMPLETE | Existing Web polling, unread badge/read handling and target routing retained. Offer/application/job/profile/chat targets route within the Web shell. Native push registration is deliberately unchanged. |
| Job subscriptions | PARTIAL | N/A | Existing subscriptions can be listed, created and deleted with the existing Firestore contract. Mobile push scheduling and background delivery are native/backend concerns, not duplicated in Web. |
| Account | COMPLETE | COMPLETE | Account summary, role-aware destinations, logout and existing account deletion service are retained. Suspension still permits Admin Inbox access. |
| Billing | N/A | COMPLETE | Uses shared `BillingService/getCompanyBillingStatus` state; plan, price, vacancy limit, trial/payment dates, setup/change/refresh/replace/cancel controls. No legacy card/manual-invoice product path is introduced. |
| Support | COMPLETE | COMPLETE | Role-specific request types; text-only, attachment-only or combined submission; photo/video/file picker, preview/removal, targeted upload errors, atomic request/admin-message/thread creation and success cleanup. |
| Admin Inbox | PARTIAL | PARTIAL | Existing thread list/read/reply path is available. Rich reply attachments, important/delete controls remain absent from the desktop Web panel. |
| Settings/legal | PARTIAL | PARTIAL | Existing notification preference keys and legal documents are available. Native biometrics, OS permission controls and mobile notification sound behavior remain native-only. |
| Reports/moderation UX | COMPLETE | COMPLETE | Profile reporting uses existing report/admin inbox schema; public held/deleted/inactive profiles are blocked and owners receive the generic suspension UX. Backend moderation actions are not duplicated in Web. |

## Controls, validation, and edge-state audit

- All introduced asynchronous submit/upload/action controls disable while busy,
  report a scoped error, and avoid updates after disposal.
- Job application checks use fresh user/job data; team submission remains in the
  existing callable so membership, capacity, duplicate, and permissions are not
  reimplemented on the client.
- Public jobs/map never reuse the Employer owner list. Owner pages retain pending,
  inactive, rejected, and draft records allowed by the existing contract.
- Chat timers are one per mounted stream, cancel on disposal, and avoid nested
  Firestore listeners. Errors retain last known data instead of permanent spinners.
- Dynamic team membership accepts legacy string and map member entries and both
  `memberStatuses` spellings. Team creation writes current and compatibility keys.
- Image/media rendering continues through existing Web-only widgets and storage
  metadata; no mobile image or upload path is changed.
- Profile/company links validate URI schemes; missing records, empty lists,
  permission errors, deleted records, and zero-result queries have terminal UI.

## MISSING AFTER THIS COMMIT

1. **Worker references editor — PARTIAL.** Existing reference data is displayed,
   but the desktop editor does not reproduce every mobile dynamic-row control.
2. **Company contacts editor — PARTIAL.** Existing contacts/phones are displayed;
   the complete mobile dynamic contacts editor is not reproduced.
3. **Profile company-job deep link — PARTIAL.** Company profile shows vacancy
   summaries; Jobs/Map and application surfaces provide full vacancy details.
4. **Admin Inbox rich replies — PARTIAL.** Text replies work; attachment replies,
   important toggles, and delete/hide controls are not exposed in the Web panel.
5. **Job subscription edit/toggle — PARTIAL.** Create/list/delete works; the
   current mobile flow itself does not provide a full edit form. Native/background
   alert delivery remains outside browser UI.
6. **Review aggregate fields — BLOCKED.** Updating another user's top-level
   `rating/reviewsCount` requires a trusted backend or rules change. Review records
   and derived display work without weakening security.
7. **Accepted-offer capacity rollback — BLOCKED.** Any reversal of an already
   accepted offer must use the authoritative slot transaction/backend. Web does
   not introduce an unsafe client-side counter write.
8. **Biometric login, native push permissions, OS calendar integration, and phone
   dialer behavior — DEFERRED native capabilities.** Browser-safe equivalents are
   used only where a reliable Web contract exists.

## Source coverage

Mobile sources reviewed include job list/details/map/filter/search/pagination,
Worker and Employer profiles, team details/create, application list/details and
offer actions, chat list/thread/media/message actions, saved jobs, subscriptions,
notifications, moderation hold/report/reviews, support/admin inbox, billing,
settings/legal, and the directly referenced models/services. Web coverage was
reviewed across `lib/web_app/pages`, `services`, `widgets`, `shell`, and `theme`.

## Platform isolation

Every implementation change in this commit is under `lib/web_app/**`. Shared
mobile files are imported only where they expose platform-neutral business
contracts (for example taxonomy, billing, offer acceptance, status utilities, and
chat creation). No mobile screen/widget/theme is imported into Web, and no
Android/iOS behavior is routed through the new code.

## Validation boundary

Static analysis and `flutter build web -t lib/main_web.dart` validate compilation,
types, imports, and the separate Web entry point. Authenticated production data
permissions, callable deployment, browser media permissions, email delivery, and
GoCardless/Firebase external state still require environment-level smoke testing
with real Worker and Employer accounts.
