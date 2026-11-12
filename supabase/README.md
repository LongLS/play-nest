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

## Membership migration

Run `migrations/20261107000000_create_membership.sql` after both survey
migrations. It preserves the survey tables and promotes existing `admin_users`
to Membership managers.

If the Membership migration was applied before 2026-11-07, also run
`migrations/20261107010000_harden_membership_dashboard.sql`. This follow-up
synchronizes existing survey admins into Membership, lets active managers view
the survey tab, and flags invoices using excluded promotions for manual review.

Then run `migrations/20261107020000_complete_admin_dashboard.sql`. It adds the
server-side paginated admin APIs, survey workflow fields, member detail and
anonymization operations, earning/redemption history, phone verification,
activity logs, and dashboard reporting series. Run migrations in filename order.

Finally run `migrations/20261107030000_add_customer_club.sql`. It links a
verified Supabase phone identity to exactly one member, adds lifetime points,
customer-only profile APIs, one-time reward codes, cancellation/refunds, and
customer data requests.

For every employee:

1. Create a separate account in **Authentication > Users**.
2. Sign in as a manager at `/admin`. Survey, Membership, earning, approval,
   redemption, and program settings are tabs in the same dashboard.
3. Open **Cấu hình > Quản lý quyền nhân viên** and grant the appropriate role.
4. Disable `active` immediately when an employee leaves.

The browser has no direct table-wide access to member phone numbers or point
balances. Exact phone lookup, earning approval, redemptions, reversals, and
adjustments use database functions with role checks and audit logs. Never put a
secret or `service_role` key in browser code.

Demo data belongs in a separate Supabase project; see `demo/README.md`.

## Browser configuration

`assets/js/supabase-config.js` contains only the project URL and Supabase
publishable key. A publishable key is expected to be visible in browser code.
Never add a secret key or legacy `service_role` key to this repository.

## Customer phone and password login

Run `migrations/20261107050000_member_password_login.sql`, then deploy the
`manage-member-auth` Edge Function. An authorized employee creates a member;
the function creates a private phone-derived Auth alias and returns a random
temporary password once. The customer signs in with phone + temporary password
and must choose a new password before viewing membership data.

Deploy with the Supabase CLI after linking the project:

```sh
supabase functions deploy manage-member-auth
supabase functions deploy manage-staff-auth
```

The function reads `SUPABASE_SERVICE_ROLE_KEY` only from Supabase's managed
server environment. Never copy that key to browser JavaScript. A forgotten
password is reset at the counter after identity verification and is recorded in
the audit log. Phone/SMS providers are not required for this flow.

## Production Club rules (2026-11-12)

Run `migrations/20261112000000_enforce_playnest_club_logic.sql` after every
`20261107...` migration. It adds versioned policy history, reward inventory and
per-member limits, configurable voucher stacking and booking limits, durable
claim codes, customer reward history, and the v2 Admin APIs used by the current
dashboard.

Important behavior:

- an invoice remains globally unique and points stay pending until Admin review;
- reward redemption and point deduction happen in one database transaction;
- claim-code validity uses each reward's configured `valid_days`;
- an expired claim does not automatically refund points;
- staff must enter the booking/invoice where a voucher is used;
- historical transactions keep their original point and reward values when
  policy settings change.

Customer authentication currently uses the phone-derived private Auth alias and
password flow described above, because the project intentionally does not
depend on a paid SMS provider. The database membership key remains the
normalized phone number. If Supabase SMS is enabled later, OTP can be added as
an alternative sign-in method without changing point or reward records.

## Submission flow

1. The browser validates the survey.
2. `assets/js/survey-storage.js` inserts the response into Supabase.
3. If the insert succeeds, the customer is redirected to
   `survey-thank-you.html`.

If the database insert fails, the form keeps the customer's answers on screen
and shows a retry message instead of navigating away.
