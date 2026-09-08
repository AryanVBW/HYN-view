"use client";

import { type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import {
  Activity,
  Bell,
  LayoutDashboard,
  Mail,
  History,
  Server,
  Users,
} from "lucide-react";

export type AdminTabId =
  | "overview"
  | "clients"
  | "client"
  | "fleet"
  | "templates"
  | "notifications"
  | "audit";

const BASE_TABS: { id: AdminTabId; label: string; icon: typeof Activity }[] = [
  { id: "overview", label: "Overview", icon: Activity },
  { id: "clients", label: "Clients", icon: Users },
  { id: "fleet", label: "Fleet", icon: Server },
  { id: "templates", label: "Email templates", icon: Mail },
  { id: "notifications", label: "Deliveries", icon: Bell },
  { id: "audit", label: "Audit trail", icon: History },
];

// A single long scroll stopped scaling once nodes, clients, deliveries and
// audit shared the page. Tabs give each concern its
// own space without hiding it behind a click that also refetches data --
// everything below is server-fetched once and just shown or hidden here.
export function AdminTabs({
  overview,
  clients,
  client,
  fleet,
  templates,
  notifications,
  audit,
  badges,
  initialActive = "overview",
}: {
  overview: ReactNode;
  clients: ReactNode;
  client?: ReactNode;
  fleet: ReactNode;
  templates: ReactNode;
  notifications: ReactNode;
  audit: ReactNode;
  badges: Partial<Record<AdminTabId, number>>;
  initialActive?: AdminTabId;
}) {
  const tabs = client
    ? [
        ...BASE_TABS.slice(0, 2),
        { id: "client" as const, label: "Client view", icon: LayoutDashboard },
        ...BASE_TABS.slice(2),
      ]
    : BASE_TABS;
  // Client links and browser history must select the panel as well as load it.
  // Reading only the initial prop left newly loaded client controls hidden.
  const searchParams = useSearchParams();
  const requested = searchParams.get("tab") ?? initialActive;
  const active = tabs.some((tab) => tab.id === requested)
    ? requested
    : requested === "client" ? "clients" : "overview";
  function selectTab(id: AdminTabId) {
    const url = new URL(window.location.href);
    url.searchParams.set("tab", id);
    // Next synchronizes useSearchParams with native history without refetching
    // the already loaded fleet, clients and delivery history on every tab click.
    window.history.pushState(null, "", `${url.pathname}${url.search}${url.hash}`);
  }
  const panels: Record<AdminTabId, ReactNode> = {
    overview,
    clients,
    client: client ?? null,
    fleet,
    templates,
    notifications,
    audit,
  };

  return (
    <div>
      <div
        role="tablist"
        aria-label="Admin sections"
        className="sticky top-[4.5rem] z-20 -mx-1 flex gap-1 overflow-x-auto border-b border-border bg-background/95 px-1 py-2 backdrop-blur-sm md:top-24"
      >
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = active === tab.id;
          const badge = badges[tab.id];
          return (
            <button
              key={tab.id}
              role="tab"
              type="button"
              aria-selected={isActive}
              id={`admin-tab-${tab.id}`}
              aria-controls={`admin-panel-${tab.id}`}
              onClick={() => selectTab(tab.id)}
              className={`flex shrink-0 items-center gap-2 rounded-full border px-3 py-2 font-mono text-xs uppercase tracking-wide transition-colors ${
                isActive
                  ? "border-primary/60 bg-primary/10 text-primary"
                  : "border-transparent text-muted-foreground hover:border-border hover:text-foreground"
              }`}
            >
              <Icon className="size-3.5" aria-hidden />
              {tab.label}
              {badge ? (
                <span
                  className={`rounded-full px-1.5 py-0.5 text-[0.6rem] leading-none ${
                    isActive ? "bg-primary text-primary-foreground" : "bg-destructive text-white"
                  }`}
                >
                  {badge}
                </span>
              ) : null}
            </button>
          );
        })}
      </div>

      <div className="mt-8 space-y-10">
        {tabs.map((tab) => (
          <div key={tab.id} id={`admin-panel-${tab.id}`} role="tabpanel" aria-labelledby={`admin-tab-${tab.id}`} hidden={active !== tab.id}>
            {panels[tab.id]}
          </div>
        ))}
      </div>
    </div>
  );
}
