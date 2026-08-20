-- notify_phone was collected but no notification delivery path consumed it.
-- Remove the unused personal-data field and its existing values.

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'notify_prefs'
       and column_name = 'notify_phone'
  ) then
    execute 'update public.notify_prefs set notify_phone = null where notify_phone is not null';
    alter table public.notify_prefs drop column notify_phone;
  end if;
end;
$$;

-- Matches the portal's existing-row update payload exactly. `user_id` remains
-- immutable; updated_at is client-supplied so a later edit can be saved.
grant update (notify_email, admin_id, updated_at) on public.notify_prefs to authenticated;
