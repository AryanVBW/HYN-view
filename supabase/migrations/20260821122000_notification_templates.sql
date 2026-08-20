-- Admin-managed email presentation without centralising delivery credentials.
-- The monitored node still sends with its own /etc/hyn-view/secrets; these
-- wrappers contain non-secret HTML and are pulled alongside ordinary config.

begin;

create table if not exists public.notification_templates (
  template_key  text primary key check (template_key in ('alert', 'report')),
  name          text not null,
  description   text not null,
  html_template text not null check (
    position('{{content}}' in html_template) > 0
    and octet_length(html_template) <= 100000
  ),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null
);

insert into public.notification_templates (template_key, name, description, html_template)
values
  ('alert', 'Incident alert', 'Wraps new, ongoing, and resolved alert digests.', '{{content}}'),
  ('report', 'Daily report', 'Wraps the scheduled daily system report.', '{{content}}')
on conflict (template_key) do nothing;

alter table public.notification_templates enable row level security;
revoke all on public.notification_templates from anon, authenticated;

create or replace function public.hyn_fetch_config(p_node_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_node public.nodes;
  v_alert_template text;
  v_report_template text;
begin
  select * into v_node from public.nodes
   where token_hash = public._hyn_sha256(p_node_token);
  if not found then raise exception 'invalid node token'; end if;
  if v_node.revoked then raise exception 'node revoked'; end if;

  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes
       set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id
     returning * into v_node;
  end if;

  update public.nodes set last_config_pull_at = now() where id = v_node.id;
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_alert_template from public.notification_templates t where t.template_key = 'alert';
  select replace(encode(convert_to(t.html_template, 'UTF8'), 'base64'), E'\n', '')
    into v_report_template from public.notification_templates t where t.template_key = 'report';

  return json_build_object(
    'status', 'ok', 'node_id', v_node.id, 'node_name', v_node.name,
    'node_status', v_node.status, 'paused_until', v_node.paused_until,
    'status_reason', v_node.status_reason, 'config', v_node.config,
    'alert_template_b64', coalesce(v_alert_template, ''),
    'report_template_b64', coalesce(v_report_template, '')
  );
end;
$$;

create or replace function public.hyn_admin_templates()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v json;
begin
  perform public._hyn_require_admin();
  select coalesce(json_agg(row_to_json(x) order by x.template_key), '[]'::json)
    into v
    from (
      select t.template_key, t.name, t.description, t.html_template, t.updated_at,
             p.email as updated_by_email
        from public.notification_templates t
        left join public.profiles p on p.id = t.updated_by
       order by t.template_key
    ) x;
  return v;
end;
$$;

create or replace function public.hyn_admin_save_template(p_template_key text, p_html_template text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public._hyn_require_admin();
  if p_template_key not in ('alert', 'report') then
    raise exception 'unknown notification template: %', p_template_key;
  end if;
  if position('{{content}}' in coalesce(p_html_template, '')) = 0 then
    raise exception 'template must include {{content}}';
  end if;
  if octet_length(p_html_template) > 100000 then raise exception 'template exceeds 100 KB'; end if;
  if p_html_template ~* '<[[:space:]]*(script|iframe|object|embed|form)([[:space:]>])'
     or p_html_template ~* '[[:space:]]on[a-z]+[[:space:]]*=' then
    raise exception 'template contains active HTML that is not allowed in email';
  end if;

  update public.notification_templates
     set html_template = p_html_template, updated_at = now(), updated_by = v_actor
   where template_key = p_template_key;
  if not found then raise exception 'notification template is not installed: %', p_template_key; end if;

  perform public._hyn_audit('notification_template.update', null, null,
    jsonb_build_object('template_key', p_template_key, 'bytes', octet_length(p_html_template)));
  return json_build_object('status', 'ok', 'template_key', p_template_key);
end;
$$;

revoke all on function public.hyn_fetch_config(text) from public;
grant execute on function public.hyn_fetch_config(text) to anon, authenticated;
revoke all on function public.hyn_admin_templates() from public;
revoke all on function public.hyn_admin_save_template(text, text) from public;
grant execute on function public.hyn_admin_templates() to authenticated;
grant execute on function public.hyn_admin_save_template(text, text) to authenticated;

commit;
