import type { MessageKind } from "./delivery-controls.ts";

// The only email this portal still sends without a human asking for it.
//
// Everything else is now administrator-triggered. A monitoring portal that mails
// unprompted is the one operators filter to a folder, and a filtered channel is
// worse than a silent one: it looks like coverage while nobody reads it. The
// fleet had already proved that -- see supabase/migrations/20260902050000, where
// a default nobody chose produced `4501 notifications failed in the last 24h`.
//
// `signin` stays automatic because it is not a digest, it is a security notice
// about an account event the account holder may not have performed. Suppressing
// it would hide an intrusion rather than reduce noise, which is the opposite of
// the point.
//
// Supabase Auth (GoTrue) owns sign-up confirmation, password change, password
// reset / forgot-password, magic-link and resend mail. Those are sent by the
// auth service and never pass through `sendManagedEmail`, so they remain
// automatic regardless of this list -- there is deliberately nothing to
// configure here for them.
export const automaticEmailKinds = ["signin"] as const;

export function automaticEmailAllowed(kind: MessageKind): boolean {
  return (automaticEmailKinds as readonly string[]).includes(kind);
}

export function manualOnlyReason(kind: MessageKind): string {
  return `Automatic "${kind}" email is switched off. An administrator sends this from the admin panel.`;
}
