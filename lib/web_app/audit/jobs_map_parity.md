# Jobs and map parity audit

Baseline before implementation: Jobs had substring search, save and single apply only. Map had clustering, viewport search and geolocation but no detail actions. Both read public/owner jobs through WebJobsDataService. Profile company queries lacked public constraints. Mobile sources reviewed: job_list_screen.dart, job_details_screen.dart, map_screen.dart, map_jobs_screen.dart, filter_sheet.dart, widgets/smart_job_search.dart, job_card.dart, job_pagination.dart, services/job_taxonomy_service.dart, job_repository.dart, models/job.dart.

| Capability | Mobile source / contract | Before | Target |
| --- | --- | --- | --- |
| Taxonomy multi-role and text search | SmartJobSearchField, JobTaxonomyService | PARTIAL | Existing taxonomy matcher |
| City/radius, hourly pay, employment types | SmartJobFilterSheet / jobMatchesSearch | MISSING | Same local matching semantics |
| Nearest/highest pay/newest; ten per page | JobListScreen | MISSING | Desktop controls |
| Saved toggle across Jobs/Map/Saved | saved_jobs/{uid}/jobs | PARTIAL | Controlled refresh plus direct write |
| Apply single/team and select team | JobDetailScreen.apply | PARTIAL | submitTeamApplication callable for team |
| Selected members/count/message on apply | Not offered by current JobDetailScreen | Not applicable | Do not invent inputs; whole team capacity check |
| Duplicate/capacity/held checks | JobDetailScreen + callable | PARTIAL | Preserve validation; authoritative callable |
| Map role/text search, cluster/selected marker/bounds | MapScreen | PARTIAL | Existing left list/right map with detail actions |
| Vacancy details/photos/company | JobDetailScreen | PARTIAL | Reuse Web details/gallery/profile routing |
| Owner statuses/public exclusion | JobRepository and Job visibility | PARTIAL | Owner query separate from constrained public query |

The target items in this focused table are implemented. Consolidated final
statuses, edge-state findings, and explicit remaining gaps are recorded in
`business_parity_matrix.md`. Authenticated production workflows still require
Worker/Employer browser sessions for end-to-end verification.
