// Read Heroku config from stdin; never log credentials or raw API responses.
let raw = "";
for await (const chunk of process.stdin) raw += chunk;
const config = JSON.parse(raw);
const base = config.NEXT_PUBLIC_SUPABASE_URL;
const key = config.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!base || !key) throw new Error("Supabase public configuration is missing");
const probes = [
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
