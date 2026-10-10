# Ask STROYKA, phase 1

Ask STROYKA is an intent layer, not a chatbot or vacancy data source. The
Worker Jobs sheet holds a short session in memory. Closing it clears the
state; no turns or transcripts are written to Firestore. The callable accepts
only `find_job` and returns a strict structured intent. It reads the signed-in
worker's trade IDs, city/region and availability. Profile contact details,
exact home address and private notes are excluded; common contact and address
patterns in the user's free text are redacted before the provider call. Operational logs
contain intent, latency, token usage or a failure category, not user text.

`AiIntentInterpreter` is the client boundary. `interpretAskStroyka` owns the
provider call and schema validation, with its API key bound as the Firebase
Secret `ASK_STROYKA_OPENAI_API_KEY`. The provider receives the latest text,
minimal profile context and structured state, not a transcript or vacancies.
The function enforces authentication, Worker role, 500-character input and
per-user request limits (5/minute, 40/day). Set
`feature_flags/ask_stroyka.enabled` to `false` for an immediate server-side
kill switch. Without a configured secret, the sheet reports unavailability and
manual Jobs search remains usable. The Jobs entry point is compiled out by
default until the secret and backend are deployed. Build with
`--dart-define=ASK_STROYKA_ENABLED=true` to expose it after verification.

The client validates trade phrases through `JobTaxonomyService`, converts the
structured intent into the existing Mobile or Web Jobs filter state, and uses
the normal vacancy feed. Date preference ranks active vacancies; an earlier
start does not exclude a vacancy still recruiting. Only the actual filtered
feed supplies result counts. No model-generated vacancy, count or free-form
ranking is displayed.

`AiAssistantIntent` reserves `findWorkers`, `createVacancy`, `workforceQuery`
and `siteQuery`, but the backend explicitly rejects these in phase 1. Future
implementations should use existing employer workflow services with a review
step before any mutation. Speech-to-text can later provide text to the same
`AiIntentInterpreter`; it must not fork search or authorization rules.
