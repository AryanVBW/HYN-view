"use client";

import { useState, type ReactNode } from "react";
import {
  Activity,
  Bell,
  History,
  Radio,
  Server,
  Users,
} from "lucide-react";

type TabId = "overview" | "channels" | "clients" | "fleet" | "notifications" | "audit";

const TABS: { id: TabId; label: string; icon: typeof Activity }[] = [
  { id: "overview", label: "Overview", icon: Activity },
  { id: "channels", label: "Your channels", icon: Radio },
  { id: "clients", label: "Clients", icon: Users },
  { id: "fleet", label: "Fleet", icon: Server },
  { id: "notifications", label: "Deliveries", icon: Bell },
  { id: "audit", label: "Audit trail", icon: History },
];

// A single long scroll stopped scaling once channel management joined nodes,
// clients, deliveries and audit on the same page. Tabs give each concern its
// own space without hiding it behind a click that also refetches data --
// everything below is server-fetched once and just shown or hidden here.
export function AdminTabs({
  overview,
  channels,
  clients,
  fleet,
  notifications,
  audit,
  badges,
}: {
  overview: ReactNode;
  channels: ReactNode;
  clients: ReactNode;
  fleet: ReactNode;
  notifications: ReactNode;
  audit: ReactNode;
  badges: Partial<Record<TabId, number>>;
}) {
  const [active, setActive] = useState<TabId>("overview");
  const panels: Record<TabId, ReactNode> = {
    overview,
    channels,
    clients,
    fleet,
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
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const isActive = active === tab.id;
          const badge = badges[tab.id];
          return (
            <button
              key={tab.id}
              role="tab"
              type="button"
              aria-selected={isActive}
              onClick={() => setActive(tab.id)}
              className={`flex shrink-0 items-center gap-2 border px-3 py-2 font-mono text-xs uppercase tracking-wide transition-colors ${
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
        {TABS.map((tab) => (
          <div key={tab.id} role="tabpanel" hidden={active !== tab.id}>
            {panels[tab.id]}
          </div>
        ))}
      </div>
    </div>
  );
}
