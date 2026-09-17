import { isD1Data, userDataRpc } from "@/lib/hyn-data";
import { createClient } from "@/lib/supabase/server";
import type { DashboardAccount } from "@/lib/permissions";
import type { AlertEvent, Metric, Node, Profile, Speedtest } from "@/lib/types";
import { NODE_COLUMNS } from "@/lib/types";
import { TELEMETRY_HOURS } from "@/lib/monitoring-state";

type PortalState = {
  userId: string;
  email: string | null;
  profile: Pick<Profile, "role" | "status"> | null;
  accounts: DashboardAccount[];
  nodes: Node[];
  error: string | null;
};

export async function loadPortalState(): Promise<{ signedOut: true } | PortalState> {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return { signedOut: true };
  if (isD1Data()) {
    const [profile, accounts, nodes] = await Promise.all([
      userDataRpc<Pick<Profile, "role" | "status">>("hyn_profile"),
      userDataRpc<DashboardAccount[]>("hyn_dashboard_accounts"),
      userDataRpc<Node[]>("hyn_list_nodes"),
    ]);
    if (accounts.error) console.error("[portal-d1] hyn_dashboard_accounts", accounts.error.message);
    if (nodes.error) console.error("[portal-d1] hyn_list_nodes", nodes.error.message);
    const profileOk = profile.data?.status === "active";
    return {
      userId: auth.user.id,
      email: auth.user.email ?? null,
      profile: profile.data,
      accounts: accounts.data ?? [],
      nodes: nodes.data ?? [],
      error: profileOk ? null : (profile.error?.message || accounts.error?.message || nodes.error?.message || null),
    };
  }
  const [profileResult, accountsResult] = await Promise.all([
    supabase.from("profiles").select("role,status").eq("id", auth.user.id).maybeSingle(),
    supabase.rpc("hyn_dashboard_accounts"),
  ]);
  const { data: nodeRows, error: nodesError } = await supabase
    .from("nodes")
    .select(NODE_COLUMNS)
    .eq("revoked", false)
    .order("is_demo", { ascending: true })
    .order("created_at", { ascending: true });
  return {
    userId: auth.user.id,
    email: auth.user.email ?? null,
    profile: profileResult.data as Pick<Profile, "role" | "status"> | null,
    accounts: (accountsResult.data ?? []) as DashboardAccount[],
    nodes: (nodeRows ?? []) as Node[],
    error: profileResult.error?.message || accountsResult.error?.message || nodesError?.message || null,
  };
}

export async function loadNodeTelemetry(nodeId: string, localMode: boolean): Promise<{
  latest: Metric | null;
  history: Metric[];
  speedtests: Speedtest[];
  alerts: AlertEvent[];
}> {
  if (localMode) return { latest: null, history: [], speedtests: [], alerts: [] };
  if (isD1Data()) {
    const [latest, history, speed, alerts] = await Promise.all([
      userDataRpc<Metric>("hyn_latest_metric", { p_node: nodeId }),
      userDataRpc<Metric[]>("hyn_metric_history", { p_node: nodeId }),
      userDataRpc<Speedtest[]>("hyn_list_speedtests", { p_node: nodeId }),
      userDataRpc<AlertEvent[]>("hyn_list_alerts", { p_node: nodeId }),
    ]);
    return {
      latest: latest.data,
      history: history.data ?? [],
      speedtests: speed.data ?? [],
      alerts: alerts.data ?? [],
    };
  }
  const supabase = await createClient();
  const since = new Date(Date.now() - TELEMETRY_HOURS * 60 * 60 * 1000).toISOString();
  const [metricsRes, historyRes, speedRes, alertRes] = await Promise.all([
    supabase.from("metrics").select("*").eq("node_id", nodeId).gte("ts", since).order("ts", { ascending: false }).limit(1),
    supabase.rpc("hyn_metric_history", { p_node: nodeId }),
    supabase.from("speedtests").select("*").eq("node_id", nodeId).gte("ts", since).order("ts", { ascending: false }).limit(14),
    supabase.from("alert_events").select("*").eq("node_id", nodeId).gte("ts", since).order("ts", { ascending: false }).limit(8),
  ]);
  return {
    latest: (metricsRes.data?.[0] ?? null) as Metric | null,
    history: (historyRes.data ?? []) as Metric[],
    speedtests: (speedRes.data ?? []) as Speedtest[],
    alerts: (alertRes.data ?? []) as AlertEvent[],
  };
}
