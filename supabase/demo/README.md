# Membership demo data

Do not run demo seed files in the production PlayNest project. Create a separate
Supabase project for presentations, apply the normal migrations there, then run
the demo seed. All demo members are marked with `is_demo = true`, and dashboard
queries exclude them from production-style totals.
