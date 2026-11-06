# PlayNest Supabase setup

The public survey client stores responses in `public.survey_responses`. Survey
results are no longer sent by email. They are available to authorized users at
`/admin`.

## Apply the database migration

1. Open the PlayNest project in the Supabase Dashboard.
2. Open **SQL Editor** and create a new query.
3. Copy and run the complete contents of
   `migrations/20261106000000_create_survey_responses.sql`.
4. Copy and run the complete contents of
   `migrations/20261106010000_create_survey_admin.sql`.
5. Confirm that `survey_responses` and `admin_users` are visible in
   **Table Editor**.

The migration:

- preserves a table that was already created in the Dashboard;
- removes the one empty connectivity-check row created on 2026-11-06;
- enables Row Level Security;
- gives signed-out visitors `INSERT` permission only;
- does not grant public `SELECT`, `UPDATE`, or `DELETE` access;
- validates rating ranges and limits the JSON response size.

## Create the admin account

1. In the Supabase Dashboard, open **Authentication > Users**.
2. Select **Add user > Create new user**.
3. Use `playnest.vn@gmail.com` and set a strong password.
4. If this account was created after running the admin migration, run this SQL:

```sql
insert into public.admin_users (user_id, email)
select id, email
from auth.users
where lower(email) = lower('playnest.vn@gmail.com')
on conflict (user_id) do update set email = excluded.email;
```

Open `/admin` and sign in with that email and password. There is no
public signup flow. Row Level Security permits survey reads only when the
signed-in user's ID exists in `admin_users`.

## Browser configuration

`assets/js/supabase-config.js` contains only the project URL and Supabase
publishable key. A publishable key is expected to be visible in browser code.
Never add a secret key or legacy `service_role` key to this repository.

## Submission flow

1. The browser validates the survey.
2. `assets/js/survey-storage.js` inserts the response into Supabase.
3. If the insert succeeds, the customer is redirected to
   `survey-thank-you.html`.

If the database insert fails, the form keeps the customer's answers on screen
and shows a retry message instead of navigating away.
