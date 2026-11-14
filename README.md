# BrainForging

A multi-course learning site on GitHub Pages. No build step needed to run it.

## Add a new course
1. Create `courses/<slug>/` with `course.json` (title, tagline, summary, level, outcomes, audience, requirements, modules with lesson titles) and `module-1.json`, `module-2.json` ... (copy the format of `courses/beckhoff-twincat-3/`).
2. In `courses/catalog.json`, add or edit the entry for `<slug>` and set `"status": "live"`. Entries with `"status": "soon"` show a Coming soon page with a Notify me form.
3. Run `python tools/build-seo.py` to refresh the search-engine syllabus inside `index.html`.
4. Commit and push.

## Database
Run `database/supabase-setup.sql` once in the Supabase SQL Editor. Accounts, progress and waiting-list sign-ups are stored there.
