-- hyn-view :: a heartbeat that is only a heartbeat
--
-- The agent used to prove it was alive by calling hyn_fetch_config, because that
-- call happened to touch last_heartbeat_at on its way past. That was fine at one
-- call a minute and is not fine at one every 24 seconds: fetch_config claims the
-- watchdog, base64-encodes two email templates, returns the whole managed config
-- and makes the API route dispatch queued notifications afterwards. None of that
-- is what a beat needs, and multiplying all of it by two and a half to learn one
-- boolean -- "this machine is still there" -- would be a self-inflicted load
-- problem on every node at once.
--
-- So the beat gets its own function. It writes one column and returns four
-- fields. The settings pull stays where it was, on the one-minute check-in.
--
-- Semantics are deliberately identical to hyn_fetch_config's for everything they
-- share: an unknown token and a revoked node are refused, a timed pause that has
-- expired resumes here too (otherwise a machine whose only traffic is beats
-- would stay paused until the next settings pull), and a paused or suspended node
-- is still recorded as alive. Suspension stops readings being accepted; it does
-- not mean an administrator wants to stop being able to see that the box is up.
create or replace function public.hyn_heartbeat(
  p_node_token text,
  p_agent_version text default null
)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_node public.nodes;
begin
  select * into v_node from public.nodes where token_hash = public._hyn_sha256(p_node_token);
  if not found then raise exception 'invalid node token'; end if;
  if v_node.revoked then raise exception 'node revoked'; end if;
  if v_node.status = 'paused' and v_node.paused_until is not null
     and v_node.paused_until <= now() then
    update public.nodes set status = 'active', paused_until = null, status_reason = null
     where id = v_node.id returning * into v_node;
  end if;
  -- last_seen_at is left alone on purpose: it means "last sent us a reading",
  -- and several portal views distinguish a node that is reachable from one that
  -- is actually reporting telemetry. A beat is not a reading.
  update public.nodes
     set last_heartbeat_at = now(),
         agent_version = coalesce(nullif(left(coalesce(p_agent_version, ''), 50), ''), agent_version)
   where id = v_node.id;
  return json_build_object(
    'status', 'ok',
    'node_id', v_node.id,
    'node_status', v_node.status,
    'heartbeat_at', now()
  );
end;
$$;

revoke all on function public.hyn_heartbeat(text, text) from public;
grant execute on function public.hyn_heartbeat(text, text) to anon, authenticated;
