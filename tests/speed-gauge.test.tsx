import assert from "node:assert/strict";
import test, { after } from "node:test";
import { registerHooks } from "node:module";
import { renderToStaticMarkup } from "react-dom/server";
import { JSDOM } from "jsdom";
import { AppRouterContext } from "next/dist/shared/lib/app-router-context.shared-runtime.js";
import type { Metric, Speedtest } from "../lib/types";

// The dashboard imports relayer styles; Node renders the real components but
// has no CSS loader. Styles do not affect these SVG scale/geometry assertions.
const styles = registerHooks({ load(url, context, nextLoad) {
  return url.endsWith(".css") ? { format: "module", source: "", shortCircuit: true } : nextLoad(url, context);
} });
after(() => styles.deregister());

const router = { back() {}, forward() {}, refresh() {}, hmrRefresh() {}, push() {}, replace() {}, prefetch() {} };
const latest: Metric = {
  id: 1, node_id: "server", ts: "2026-09-13T00:00:00Z", cpu_pct: null,
  cpu_temp_c: null, cpu_mhz: null, cpu_model: null, cpu_steal: null, cpu_iowait: null,
  cpu_cores: null, load1: null, mem_pct: null, mem_total: null, mem_used: null,
  swap_used: null, disk_pct: null, uptime_s: null, net_iface: null, net_rx_bps: null,
  net_tx_bps: null, net_retrans_pm: null, latency_ms: null, net_link_mbps: null,
  psi_cpu: null, psi_mem: null, psi_io: null, tcp_estab: null, conntrack_pct: null,
  proc_count: null, sensors: null, payload: null,
};

for (const mbps of [0, 500, 1000, 1250]) {
  test(`both internet dials use a 1 Gbps scale and preserve a ${mbps} Mbps reading`, async () => {
    const { SimpleDashboard } = await import("../components/dashboard/simple-dashboard");
    const speedtests: Speedtest[] = mbps === 0 ? [] : [{
      id: 1, node_id: "server", ts: new Date().toISOString(),
      down_bps: mbps * 125_000, up_bps: 0, latency_ms: 5, note: null,
    }];
    const html = renderToStaticMarkup(
      <AppRouterContext.Provider value={router}>
        <SimpleDashboard node={{ name: "Server", last_seen_at: null }} latest={latest} speedtests={speedtests} />
      </AppRouterContext.Provider>,
    );
    const dom = new JSDOM(html);
    try {
      const gauges = dom.window.document.querySelectorAll('svg[aria-label^="Fastest today:"], svg[aria-label^="Highest speed possible:"]');
      assert.equal(gauges.length, 2);
      for (const gauge of gauges) {
        assert.ok(gauge.getAttribute("aria-label")?.includes(`${mbps.toFixed(1)} of 1000 Mbps`));
        const labels = Array.from(gauge.querySelectorAll("g > text"), text => text.textContent);
        assert.deepEqual(labels, ["0", "100", "200", "300", "400", "500", "600", "700", "800", "900", "1.0k"]);
        assert.equal(gauge.querySelector('text[y="150"]')?.textContent, mbps < 10 ? mbps.toFixed(1) : String(mbps));
      }
      if (mbps === 500) {
        // A 500 Mbps comparison belongs halfway round the 1 Gbps dial, at its
        // top, instead of being pinned to the old 300 Mbps scale's endpoint.
        const marker = gauges[0].querySelector('line[stroke="#e8a400"]');
        assert.ok(marker);
        assert.ok(Math.abs(Number(marker.getAttribute("x1")) - 120) < 0.001);
        assert.equal(Number(marker.getAttribute("y1")), 49);
      }
    } finally {
      dom.window.close();
    }
  });
}
