export const portalRoles = [
  "viewer",
  "monitor",
  "maintainer",
  "admin",
  "super_admin",
] as const;
export type PortalRole = (typeof portalRoles)[number];
export const roleLabels: Record<PortalRole, string> = {
  viewer: "Viewer",
  monitor: "Monitor",
  maintainer: "Maintainer",
  admin: "Admin",
  super_admin: "Super admin",
};
export const roleDescriptions: Record<PortalRole, string> = {
  viewer: "View dashboards shared with you.",
  monitor:
    "Link your devices, view shared servers, refresh readings, and request relayer access.",
  maintainer:
    "Watch every server on one combined 24/7 dashboard, refresh readings, and send a notification or report for any server on demand. Administers nothing.",
  admin: "Link your devices, view every dashboard, and add other admins.",
  super_admin:
    "Manage machines, relayers, settings, roles, and dashboard sharing.",
};
export function normalizeRole(role: unknown): PortalRole {
  return portalRoles.includes(role as PortalRole)
    ? (role as PortalRole)
    : "viewer";
}
export function permissions(role: unknown) {
  return {
    canWrite: role === "super_admin",
    canLink: role === "monitor" || role === "admin" || role === "super_admin",
    canSync:
      role === "super_admin" || role === "monitor" || role === "maintainer",
    canRequest: role === "super_admin" || role === "monitor",
    canAdmin: role === "super_admin" || role === "admin",
    // Fleet-wide read, deliberately separate from canAdmin. A Maintainer sees
    // every server but inherits none of the administrative write powers that
    // canAdmin carries (roles, suspension, deletion, templates, sharing) --
    // mirrors hyn_can_view_fleet() vs hyn_is_admin() in the database, which is
    // where the boundary is actually enforced.
    canViewFleet:
      role === "super_admin" || role === "admin" || role === "maintainer",
    // May trigger a manual notification or report send. Every non-auth email is
    // manual now (see lib/email-automation.ts), so this is what replaces the
    // schedules that used to send by themselves.
    canNotify:
      role === "super_admin" || role === "admin" || role === "maintainer",
    isMaintainer: role === "maintainer",
  };
}
export type DashboardAccount = { id: string; name: string; own: boolean; relayers?: boolean };
