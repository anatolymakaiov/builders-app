# Firebase Backend Setup

This file documents the staged backend setup for the current app architecture.

Nothing should be applied to Firebase without explicit approval.

## Prepared Files

- `firestore.rules` - Firestore access rules for users, jobs, applications, chats, reports, support requests, payment requests, plans, and legacy MVP collections.
- `storage.rules` - Firebase Storage rules for profile photos, company photos, job photos, team media, and chat media.
- `firestore.indexes.json` - Composite indexes for current compound queries.
- `scripts/firebase_backend_setup.js` - Dry-run-first helper for seed and migration tasks.

## Required One-Time Local Setup

Install the function dependencies before running the setup script:

```bash
cd functions
npm install
cd ..
```

The setup script uses `firebase-admin` from the local dependencies.

## Safe Dry Runs

Dry-run mode is the default. These commands do not write data:

```bash
node scripts/firebase_backend_setup.js --seed-plans
node scripts/firebase_backend_setup.js --set-admin=9Oa3R9BuludbqurFhOCoinduNih2
node scripts/firebase_backend_setup.js --backfill-jobs
node scripts/firebase_backend_setup.js --trial-billing-all
node scripts/firebase_backend_setup.js --normalize-payment-requests
```

## Apply Data Changes

Only run with `--commit` after explicit approval:

```bash
node scripts/firebase_backend_setup.js --seed-plans --commit
node scripts/firebase_backend_setup.js --set-admin=9Oa3R9BuludbqurFhOCoinduNih2 --commit
node scripts/firebase_backend_setup.js --backfill-jobs --commit
node scripts/firebase_backend_setup.js --trial-billing-all --commit
node scripts/firebase_backend_setup.js --normalize-payment-requests --commit
```

For a single employer trial:

```bash
node scripts/firebase_backend_setup.js --trial-billing=EMPLOYER_UID --commit
```

## Deploy Rules And Indexes

Only deploy after explicit approval:

```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
firebase deploy --only firestore:indexes
```

## Current Admin UID

```text
9Oa3R9BuludbqurFhOCoinduNih2
```
