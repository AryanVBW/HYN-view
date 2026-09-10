export type ServerNotification = {
  id: string; node_id: string; owner: string; node_name: string;
  ts: string; severity: "info" | "warn" | "crit";
  message: string; kind: "alert" | "resolved" | "command" | "offline";
};

export function unreadNotifications(events: ServerNotification[], read: string[]) {
  const ids = new Set(read);
  return events.filter(event => !ids.has(event.id));
}

export function notificationLink(event: Pick<ServerNotification, "node_id" | "owner">) {
  return `/dashboard?${new URLSearchParams({ node: event.node_id, owner: event.owner })}`;
}
