// Read Heroku config from stdin; never log credentials or raw API responses.
let raw = "";
for await (const chunk of process.stdin) raw += chunk;
const config = JSON.parse(raw);
const base = config.NEXT_PUBLIC_SUPABASE_URL;
const key = config.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!base || !key) throw new Error("Supabase public configuration is missing");

const dataApi = typeof config.HYN_DATA_API_URL === "string" ? config.HYN_DATA_API_URL.replace(/\/$/, "") : "";
if (dataApi) {
  if (!config.HYN_DATA_SERVICE_KEY) {
    throw new Error("D1 cutover requires HYN_DATA_SERVICE_KEY on the deployment");
  }
  const response = await fetch(`${dataApi}/health`, { signal: AbortSignal.timeout(15000) });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.store !== "d1") {
    throw new Error("Database release gate failed for the D1 worker health check. Deploy cloudflare/ and set HYN_DATA_API_URL to that origin.");
  }
  console.log("PASS D1 worker is reachable and serving application data");
  process.exit(0);
}

if (!config.SUPABASE_SERVICE_ROLE_KEY) throw new Error("Managed delivery controls require SUPABASE_SERVICE_ROLE_KEY on the deployment");
const probes = [
  ["hyn_metric_history", {p_node:null}, "not authenticated"],
  ["hyn_fleet_metric_history", {}, "not authenticated"],
  ["hyn_prune_telemetry", {p_batch:1}, "permission denied"],
  ["hyn_admin_delivery_dashboard", {p_owner:null,p_kind:"all",p_status:"all",p_offset:0}, "not authenticated"],
  ["hyn_admin_set_delivery_rules", {p_owner:null,p_rules:[]}, "not authenticated"],
  ["hyn_admin_set_digest", {p_owner:null,p_enabled:false,p_at:"08:00",p_timezone:"UTC",p_inherit:false,p_confirm_all:false}, "not authenticated"],
  ["hyn_admin_stop_delivery", {p_event:null}, "not authenticated"],
  ["hyn_reserve_delivery", {p_key:"release-probe",p_kind:"daily",p_owner:null,p_node:null,p_recipient:"probe@example.invalid",p_subject:"No send",p_nodes:[]}, "permission denied"],
  ["hyn_complete_delivery", {p_attempt:null,p_status:"failed",p_provider_id:null,p_error:null}, "permission denied"],
  ["hyn_due_user_digests", {p_trigger_node:null}, "permission denied"],
  ["hyn_user_digest_content", {p_owner:null}, "permission denied"],
  ["hyn_defer_web_delivery", {p_job:null,p_reason:"No send"}, "permission denied"],
  // The dashboard needs the roles migration even before it loads a server.
  ["hyn_dashboard_accounts", {}, "not authenticated"],
  ["hyn_is_super_admin", {}, "not authenticated"],
  ["hyn_can_link", {}, "not authenticated"],
  ["hyn_admin_set_server_access", {p_viewer:null,p_node:null,p_allow:false}, "not authenticated"],
  ["hyn_bandwidth_report", {p_node:null,p_days:30}, "not authenticated"],
  ["hyn_admin_share_server", {p_viewers:[],p_node:null,p_allow:false,p_notify:false}, "not authenticated"],
  ["hyn_fleet_bandwidth_report", {p_days:30}, "not authenticated"],
  ["hyn_server_notifications", {p_limit:50}, "not authenticated"],
  ["hyn_record_bandwidth", {p_node_token:"hyn-release-invalid-token",p_iface:"eth0",p_boot_id:"release-check",p_rx:0,p_tx:0}, "invalid node token"],
];
for (const [name, body, expected] of probes) {
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method:"POST", headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json"},
    body:JSON.stringify(body), signal:AbortSignal.timeout(15000),
  });
  const result = await response.json();
  // Authenticated-only functions should be inaccessible to anon before their
  // body runs. PGRST202 is a missing migration, not an authorization success.
  const denied = result.code === "42501" && (response.status === 401 || response.status === 403);
  if (response.ok || !(denied || result.message === expected)) {
    throw new Error(`Database release gate failed for ${name} (HTTP ${response.status}, code ${result.code ?? "unknown"}). Apply the matching CLI/database migrations first.`);
  }
  console.log(`PASS ${name} exists and rejects unauthenticated mutation`);
}
