"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  normalizeRole,
  permissions,
  roleDescriptions,
  roleLabels,
  type DashboardAccount,
} from "@/lib/permissions";

export function DashboardContext({
  role,
  accounts,
  owner,
}: {
  role: unknown;
  accounts: DashboardAccount[];
  owner: string;
}) {
  const router = useRouter();
  const normalized = normalizeRole(role);
  return (
    <section
      className="mb-8 flex flex-col gap-5 border-b border-border pb-6 sm:flex-row sm:items-end sm:justify-between"
      aria-label="Dashboard access"
    >
      <div>
        <div className="flex flex-wrap items-center gap-3">
          <p className="section-kicker">// your workspace</p>
          <span className="rounded-full border border-primary/40 bg-primary/10 px-3 py-1 font-mono text-xs text-primary">
            {roleLabels[normalized]}
          </span>
          {permissions(role).canAdmin ? (
            <Link
              href="/admin"
              className="font-mono text-xs text-primary underline underline-offset-4"
            >
              Admin dashboard
            </Link>
          ) : null}
        </div>
        <p className="mt-3 font-mono text-xs leading-6 text-muted-foreground">
          {roleDescriptions[normalized]}
        </p>
      </div>
      <label className="flex min-w-0 flex-col gap-2 font-mono text-xs text-muted-foreground sm:max-w-sm">
        Viewing dashboard
        <select
          value={owner}
          onChange={(event) =>
            router.push(
              `/dashboard?owner=${encodeURIComponent(event.target.value)}`,
            )
          }
          className="w-full rounded-md border border-input bg-background px-3 py-2.5 text-sm text-foreground focus-visible:outline-primary"
        >
          {accounts.map((account) => (
            <option key={account.id} value={account.id}>
              {account.name}
            </option>
          ))}
        </select>
      </label>
    </section>
  );
}
