-- ===========================================================================
-- email templates: list every message the portal actually sends
-- ===========================================================================
-- The template store admitted three keys -- alert, report, system -- while the
-- code sent six kinds of mail. The sign-in notice, the device-linked
-- confirmation and the first system report were rendered straight through
-- renderHynEmailShell(), so they had no row here, never appeared in the admin
-- panel's template list, and could not be edited at all. An administrator
-- looking at that tab saw three entries and no way to reach half the mail their
-- customers receive.
--
-- Widening the constraint and seeding the missing rows is only half of it; the
-- three senders are switched to renderManagedHynEmail() in the same change, so a
-- saved wrapper actually reaches them.
alter table public.notification_templates
  drop constraint if exists notification_templates_template_key_check;
alter table public.notification_templates
  add constraint notification_templates_template_key_check
  check (template_key in ('alert','report','system','signin','device','first_report'));

insert into public.notification_templates (template_key, name, description, html_template)
values
  ('signin', 'Sign-in notice',
   'Wraps the security notice sent when an account signs in. This is the one message that still sends automatically.',
   '{{content}}'),
  ('device', 'Device linked',
   'Wraps the confirmation sent when a machine finishes pairing.',
   '{{content}}'),
  ('first_report', 'First system report',
   'Wraps the inventory sent after a newly linked machine uploads its first complete reading.',
   '{{content}}')
on conflict (template_key) do nothing;

-- Keep the three originals' copy honest about the fact that scheduled sending is
-- off: these now go out when an administrator or maintainer asks for them.
update public.notification_templates
   set description = 'Wraps new, ongoing and resolved alert digests, and the outage watchdog notice. Sent on request.'
 where template_key = 'alert';
update public.notification_templates
   set description = 'Wraps the 24-hour performance digest and any report sent from the admin or fleet panel. Sent on request.'
 where template_key = 'report';
update public.notification_templates
   set description = 'Wraps the hardware, software and service inventory, and command results. Sent on request.'
 where template_key = 'system';

-- The save RPC validates the key independently of the CHECK constraint (it is the
-- boundary a browser session actually hits), so widening one without the other
-- would list six templates in the panel and refuse to save three of them.
create or replace function public.hyn_admin_save_template(
  p_template_key text,
  p_html_template text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_actor uuid;
begin
  v_actor := public._hyn_require_admin();
  if p_template_key not in ('alert','report','system','signin','device','first_report') then
    raise exception 'unknown notification template: %', p_template_key;
  end if;
  if position('{{content}}' in coalesce(p_html_template, '')) = 0 then
    raise exception 'template must include {{content}}';
  end if;
  if octet_length(p_html_template) > 100000 then
    raise exception 'template exceeds 100 KB';
  end if;
  if p_html_template ~* '<[[:space:]]*(script|iframe|object|embed|form)([[:space:]>])'
     or p_html_template ~* '[[:space:]]on[a-z]+[[:space:]]*=' then
    raise exception 'template contains active HTML that is not allowed in email';
  end if;

  update public.notification_templates
     set html_template = p_html_template,
         updated_at = now(),
         updated_by = v_actor
   where template_key = p_template_key;
  if not found then
    raise exception 'notification template is not installed: %', p_template_key;
  end if;

  perform public._hyn_audit('notification_template.update', null, null,
    jsonb_build_object('template_key', p_template_key, 'bytes', octet_length(p_html_template)));
  return json_build_object('status', 'ok', 'template_key', p_template_key);
end;
$$;
revoke all on function public.hyn_admin_save_template(text, text) from public, anon;
grant execute on function public.hyn_admin_save_template(text, text) to authenticated;
