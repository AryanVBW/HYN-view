export const portalRoles = [
  "viewer",
  "monitor",
  "admin",
  "super_admin",
] as const;
export type PortalRole = (typeof portalRoles)[number];
export const roleLabels: Record<PortalRole, string> = {
  viewer: "Viewer",
  monitor: "Monitor",
  admin: "Admin",
  super_admin: "Super admin",
};
export const roleDescriptions: Record<PortalRole, string> = {
  viewer: "View dashboards shared with you.",
  monitor:
    "Link your devices, view shared servers, refresh readings, and request relayer access.",
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
    canSync: role === "super_admin" || role === "monitor",
    canRequest: role === "super_admin" || role === "monitor",
    canAdmin: role === "super_admin" || role === "admin",
  };
}
export type DashboardAccount = { id: string; name: string; own: boolean; relayers?: boolean };
