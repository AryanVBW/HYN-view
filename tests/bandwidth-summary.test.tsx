import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { BandwidthSummary } from "../components/dashboard/bandwidth-summary";
import type { BandwidthReport } from "../lib/bandwidth";

const report: BandwidthReport = {
  sampled_at: "2026-09-11T08:00:00Z", since: "2026-09-01", iface: "eth0",
  ingress_bytes: "1073741824", egress_bytes: "2147483648", days: [],
};

test("user consumption shows accurate received, sent and total counters without report controls", () => {
  const html = renderToStaticMarkup(<BandwidthSummary report={report} />);
  for (const value of ["1.00 GiB", "2.00 GiB", "3.00 GiB", "Received", "Sent", "Total transferred", "2026-09-01", "2026-09-11 08:00 UTC"]) assert.ok(html.includes(value), value);
  assert.doesNotMatch(html, /<select|<form|<table|<button|All accessible servers|Advanced view/);
});

test("missing samples and failed readings never masquerade as zero usage", () => {
  for (const value of [null, {...report, sampled_at: null}]) {
    const html = renderToStaticMarkup(<BandwidthSummary report={value} />);
    assert.match(html, /No usage readings yet/);
    assert.doesNotMatch(html, /0\.00 B|GiB/);
  }
  const error = renderToStaticMarkup(<BandwidthSummary report={report} error />);
  assert.match(error, /temporarily unavailable/);
  assert.doesNotMatch(error, /GiB/);
  const zero = renderToStaticMarkup(<BandwidthSummary report={{...report, ingress_bytes: "0", egress_bytes: "0"}} />);
  assert.equal(zero.match(/0\.00 B/g)?.length, 3);
});

test("large counters preserve integer byte precision", () => {
  const html = renderToStaticMarkup(<BandwidthSummary report={{...report, ingress_bytes: "9007199254740993", egress_bytes: "9"}} />);
  assert.match(html, /title="9007199254741002 bytes"/);
});
