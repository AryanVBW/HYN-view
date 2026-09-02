import type { NotificationLogRow } from "./types";

// "Clear" on the account page's delivery history hides rows; it does not delete
// them. The records stay in notification_log -- an administrator still reads the
// fleet-wide log, the 30-day counters above the panel still count, and the client
// can put their own view back -- because a delivery someone chose not to look at
// is not the same fact as a delivery that never happened.
//
// The cutoff lives in a cookie rather than localStorage so the server render does
// the filtering: state in the browser would mean shipping the rows, painting
// them, and hiding them a frame later.
export const DELIVERY_CLEARED_COOKIE = "hyn_delivery_cleared_at";

// A year, matching the dashboard view-mode cookie: long enough to be permanent
// for a view preference without living in the cookie jar for ever.
export const DELIVERY_CLEARED_MAX_AGE = 60 * 60 * 24 * 365;

// A cookie is user-controlled input, so anything that is not the ISO timestamp we
// write ourselves is treated as no cutoff at all. Both halves of that matter:
// NaN comparisons are always false, so a junk value would silently blank the
// panel and read as "we lost your delivery history"; and Date.parse accepts far
// more than ISO -- `Date.parse("0")` is 1 January 2000 -- so a shape check has to
// come first for a stray cookie to be rejected rather than honoured.
export function visibleDeliveries(
  log: NotificationLogRow[],
  cookieValue: string | null | undefined
): { rows: NotificationLogRow[]; cleared: boolean } {
  const cutoff = /^\d{4}-\d{2}-\d{2}T/.test(cookieValue ?? "")
    ? Date.parse(cookieValue as string)
    : Number.NaN;
  if (Number.isNaN(cutoff)) return { rows: log, cleared: false };
  // Compared as instants rather than as strings: both sides are ISO timestamps
  // from Postgres today, but a string compare would quietly stop working the day
  // one of them arrives with a different offset or fractional precision.
  return { rows: log.filter((row) => Date.parse(row.ts) > cutoff), cleared: true };
}
