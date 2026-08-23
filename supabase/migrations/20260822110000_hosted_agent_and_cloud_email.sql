-- Hosted agent configuration and centrally delivered, customer-scheduled email.

create or replace function public._hyn_portal_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare e record; v text;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then return false; end if;
  for e in select key, value from jsonb_each(p_config) loop
    if jsonb_typeof(e.value) not in ('number', 'string') then return false; end if;
    v := e.value #>> '{}';
    case
      when e.key in ('alert_mem_pct', 'alert_disk_pct') then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 100 then return false; end if;
      when e.key = 'alert_temp_c' then
        if v !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
        if v::integer > 200 then return false; end if;
      when e.key = 'alert_load_per_core' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'alert_latency_ms' then
        if v !~ '^(0|[1-9][0-9]{0,5})$' then return false; end if;
        if v::integer > 600000 then return false; end if;
      when e.key = 'alert_repeat_hours' then
        if v !~ '^(0|[1-9][0-9]{0,3})$' then return false; end if;
        if v::integer > 8760 then return false; end if;
      when e.key = 'notify_max_per_day' then
        if v !~ '^(0|[1-9][0-9]{0,4})$' then return false; end if;
        if v::integer > 10000 then return false; end if;
      when e.key = 'cloud_push_min' then
        if v !~ '^[1-9][0-9]{0,3}$' then return false; end if;
        if v::integer > 1440 then return false; end if;
      when e.key = 'alert_min_severity' then
        if v not in ('crit', 'warn', 'info') then return false; end if;
      when e.key = 'auto_update' then
        if v not in ('install', 'check', 'off') then return false; end if;
      when e.key = 'report_at' then
        if v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
      else return false;
    end case;
  end loop;
  return true;
end;
$$;

update public.nodes n
   set config = coalesce((
     select jsonb_object_agg(e.key, e.value)
       from jsonb_each(case when jsonb_typeof(n.config) = 'object' then n.config else '{}'::jsonb end) e
      where e.key = any (array[
        'alert_mem_pct', 'alert_disk_pct', 'alert_temp_c', 'alert_load_per_core',
        'alert_latency_ms', 'alert_min_severity', 'alert_repeat_hours', 'report_at',
        'notify_max_per_day', 'cloud_push_min', 'auto_update'
      ]::text[])
        and public._hyn_portal_config_valid(jsonb_build_object(e.key, e.value))
   ), '{}'::jsonb);

alter table public.nodes drop constraint if exists nodes_config_portal_keys_check;
alter table public.nodes add constraint nodes_config_portal_keys_check
  check (public._hyn_portal_config_valid(config));

alter table public.notification_templates
  drop constraint if exists notification_templates_template_key_check;
alter table public.notification_templates
  add constraint notification_templates_template_key_check
  check (template_key in ('alert', 'report', 'system'));

update public.notification_templates
   set name = 'Daily health digest',
       description = 'Wraps the scheduled 24-hour performance digest.'
 where template_key = 'report';
insert into public.notification_templates (template_key, name, description, html_template)
values ('system', 'System information', 'Wraps the scheduled hardware, software, and service inventory.', '{{content}}')
on conflict (template_key) do nothing;

create table if not exists public.email_preferences (
  node_id uuid primary key references public.nodes (id) on delete cascade,
  recipient text not null check (recipient ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  timezone text not null default 'UTC' check (octet_length(timezone) between 1 and 80),
  incident_enabled boolean not null default true,
  daily_enabled boolean not null default true,
  daily_at time not null default '08:00',
  system_enabled boolean not null default true,
  system_at time not null default '09:00',
  last_daily_local_date date,
  last_system_local_date date,
  last_alert_id bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.email_preferences enable row level security;
drop policy if exists email_preferences_select_own on public.email_preferences;
create policy email_preferences_select_own on public.email_preferences for select
  using (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));
drop policy if exists email_preferences_insert_own on public.email_preferences;
create policy email_preferences_insert_own on public.email_preferences for insert
  with check (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));
drop policy if exists email_preferences_update_own on public.email_preferences;
create policy email_preferences_update_own on public.email_preferences for update
  using (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()))
  with check (exists (select 1 from public.nodes n where n.id = email_preferences.node_id and n.owner = auth.uid()));

create or replace function public._hyn_create_email_preferences()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_demo = false then
    insert into public.email_preferences (node_id, recipient)
      select new.id, p.email from public.profiles p where p.id = new.owner and p.email is not null
    on conflict (node_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists hyn_node_email_preferences on public.nodes;
create trigger hyn_node_email_preferences after insert on public.nodes
  for each row execute function public._hyn_create_email_preferences();
insert into public.email_preferences (node_id, recipient)
select n.id, p.email from public.nodes n join public.profiles p on p.id = n.owner
 where n.is_demo = false and p.email is not null
on conflict (node_id) do nothing;

create table if not exists public.cloud_email_dispatches (
  idempotency_key text primary key,
  node_id uuid not null references public.nodes (id) on delete cascade,
  kind text not null check (kind in ('alert', 'report', 'system')),
  created_at timestamptz not null default now(),
  provider_id text
);
alter table public.cloud_email_dispatches enable row level security;
revoke all on public.cloud_email_dispatches from anon, authenticated;
grant select, insert, update, delete on public.email_preferences to authenticated;

create or replace function public.hyn_admin_save_template(p_template_key text, p_html_template text)
returns json language plpgsql security definer set search_path = public as $$
declare v_actor uuid;
begin
  v_actor := public._hyn_require_admin();
  if p_template_key not in ('alert', 'report', 'system') then raise exception 'unknown notification template: %', p_template_key; end if;
  if position('{{content}}' in coalesce(p_html_template, '')) = 0 then raise exception 'template must include {{content}}'; end if;
  if octet_length(p_html_template) > 100000 then raise exception 'template exceeds 100 KB'; end if;
  if p_html_template ~* '<[[:space:]]*(script|iframe|object|embed|form)([[:space:]>])'
     or p_html_template ~* '[[:space:]]on[a-z]+[[:space:]]*=' then
    raise exception 'template contains active HTML that is not allowed in email';
  end if;
  update public.notification_templates set html_template = p_html_template, updated_at = now(), updated_by = v_actor
   where template_key = p_template_key;
  if not found then raise exception 'notification template is not installed: %', p_template_key; end if;
  perform public._hyn_audit('notification_template.update', null, null,
    jsonb_build_object('template_key', p_template_key, 'bytes', octet_length(p_html_template)));
  return json_build_object('status', 'ok', 'template_key', p_template_key);
end;
$$;
revoke all on function public.hyn_admin_save_template(text, text) from public;
grant execute on function public.hyn_admin_save_template(text, text) to authenticated;
