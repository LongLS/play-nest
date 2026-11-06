create table if not exists public.survey_responses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  form_version text not null default '1',
  source text not null default 'playnest-survey',
  service_rating smallint not null,
  food_rating smallint not null,
  staff_name text,
  staff_rating smallint not null,
  answers jsonb not null default '{}'::jsonb,
  page_url text,

  constraint survey_service_rating_range
    check (service_rating between 1 and 5),
  constraint survey_food_rating_range
    check (food_rating between 1 and 5),
  constraint survey_staff_rating_range
    check (staff_rating between 1 and 5),
  constraint survey_staff_name_length
    check (staff_name is null or char_length(staff_name) <= 120),
  constraint survey_answers_is_object
    check (jsonb_typeof(answers) = 'object'),
  constraint survey_answers_size
    check (octet_length(answers::text) <= 50000)
);

-- Keep this migration compatible with a table created earlier in the Dashboard.
alter table public.survey_responses
  add column if not exists form_version text,
  add column if not exists source text,
  add column if not exists service_rating smallint,
  add column if not exists food_rating smallint,
  add column if not exists staff_name text,
  add column if not exists staff_rating smallint,
  add column if not exists answers jsonb,
  add column if not exists page_url text;

alter table public.survey_responses
  alter column form_version set default '1',
  alter column source set default 'playnest.vn/survey.html',
  alter column answers set default '{}'::jsonb;

update public.survey_responses
set
  form_version = coalesce(form_version, '1'),
  source = coalesce(source, 'playnest-survey'),
  answers = coalesce(answers, '{}'::jsonb);

-- Remove the single empty connectivity-check row created on 2026-11-06.
delete from public.survey_responses
where created_at between '2026-11-06 08:14:30+00' and '2026-11-06 08:15:30+00'
  and service_rating is null
  and food_rating is null
  and staff_rating is null
  and staff_name is null
  and answers = '{}'::jsonb;

alter table public.survey_responses
  alter column form_version set not null,
  alter column source set not null,
  alter column service_rating set not null,
  alter column food_rating set not null,
  alter column staff_rating set not null,
  alter column answers set not null;

alter table public.survey_responses
  drop constraint if exists service_rating_range,
  drop constraint if exists food_rating_range,
  drop constraint if exists staff_rating_range,
  drop constraint if exists answers_must_be_object,
  drop constraint if exists survey_service_rating_range,
  drop constraint if exists survey_food_rating_range,
  drop constraint if exists survey_staff_rating_range,
  drop constraint if exists survey_staff_name_length,
  drop constraint if exists survey_answers_is_object,
  drop constraint if exists survey_answers_size;

alter table public.survey_responses
  add constraint survey_service_rating_range
    check (service_rating between 1 and 5),
  add constraint survey_food_rating_range
    check (food_rating between 1 and 5),
  add constraint survey_staff_rating_range
    check (staff_rating between 1 and 5),
  add constraint survey_staff_name_length
    check (staff_name is null or char_length(staff_name) <= 120),
  add constraint survey_answers_is_object
    check (jsonb_typeof(answers) = 'object'),
  add constraint survey_answers_size
    check (octet_length(answers::text) <= 50000);

comment on table public.survey_responses is
  'Customer feedback submitted from playnest.vn/survey.html';

alter table public.survey_responses enable row level security;

revoke all on table public.survey_responses from anon, authenticated;
grant insert on table public.survey_responses to anon, authenticated;

drop policy if exists "Visitors can submit survey responses"
  on public.survey_responses;

create policy "Visitors can submit survey responses"
on public.survey_responses
for insert
to anon, authenticated
with check (
  source = 'playnest.vn/survey.html'
  and form_version = '1'
  and service_rating between 1 and 5
  and food_rating between 1 and 5
  and staff_rating between 1 and 5
  and jsonb_typeof(answers) = 'object'
  and octet_length(answers::text) <= 50000
);
