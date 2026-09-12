import Link from "next/link";
import { Bell, RadioTower, Server } from "lucide-react";
import { cn } from "@/lib/utils";

type DashboardSection = "servers" | "relayers" | "notifications";

export function DashboardNavigation({
  section,
  serverHref = "/dashboard",
  canViewRelayers = true,
}: {
  section: DashboardSection;
  serverHref?: string;
  canViewRelayers?: boolean;
}) {
  const items = [
    { id: "servers", label: "Servers", href: serverHref, icon: Server },
    ...(canViewRelayers ? [{ id: "relayers", label: "Relayers", href: "/dashboard?section=relayers", icon: RadioTower }] : []),
    { id: "notifications", label: "Notifications", href: "/notifications", icon: Bell },
  ];

  return (
    <nav aria-label="Dashboard sections" className="grid w-full min-w-0 auto-cols-fr grid-flow-col gap-1 rounded-2xl border border-border bg-card p-1.5 shadow-sm sm:w-auto sm:rounded-full">
      {items.map(({ id, label, href, icon: Icon }) => (
        <Link
          key={id}
          href={href}
          aria-current={section === id ? "page" : undefined}
          className={cn(
            "flex min-h-14 min-w-0 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-center text-[13px] font-semibold leading-5 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground motion-reduce:transition-none sm:min-h-12 sm:flex-row sm:gap-2 sm:rounded-full sm:px-5 sm:text-sm",
            section === id
              ? "bg-foreground text-background shadow-sm"
              : "text-foreground hover:bg-muted",
          )}
        >
          <Icon className="size-4 shrink-0" aria-hidden="true" />
          <span>{label}</span>
        </Link>
      ))}
    </nav>
  );
}
