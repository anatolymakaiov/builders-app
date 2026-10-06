# Calendar provider foundation

STROYKA assignments, vacancies, sites and worker unavailability remain the
source of truth. `CalendarExportEvent` is a safe outbound projection, and the
ICS provider serializes it without reading profiles or writing any calendar
state. Browser download and native Add to Calendar are delivery mechanisms.

Google and Outlook are deliberately unavailable in `providerCapabilities`.
Neither OAuth scopes nor tokens are requested or stored. A future first sync
should be one-way from STROYKA to the user's selected external calendar. That
work needs provider OAuth consent, a server-side refresh-token strategy,
calendar selection, revocation/disconnect, retry handling, and a server-owned
mapping of provider, internal source type/ID, external calendar/event IDs,
last sync time and status. No external edits should mutate STROYKA until a
separate two-way conflict and authorization design exists.
