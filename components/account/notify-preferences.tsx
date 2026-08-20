"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import type { AdminOption, NotifyPrefs } from "@/lib/types";

// Everything a client configures for notifications, full stop: an email, an
// optional phone number, and which administrator manages delivery. The actual
// provider (Resend, SMTP, Telegram, ...) is the chosen admin's problem, set up
// once in the admin panel -- see components/admin/channel-manager.tsx.
export function NotifyPreferences({
  prefs,
  admins,
  userEmail,
}: {
  prefs: NotifyPrefs | null;
  admins: AdminOption[];
  userEmail: string | null | undefined;
}) {
  const router = useRouter();
  const [email, setEmail] = useState(prefs?.notify_email ?? userEmail ?? "");
  const [phone, setPhone] = useState(prefs?.notify_phone ?? "");
  const [adminId, setAdminId] = useState(prefs?.admin_id ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    const supabase = createClient();
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) {
      setBusy(false);
      setError("Your session expired. Refresh and sign in again.");
      return;
    }
    const { error } = await supabase.from("notify_prefs").upsert({
      user_id: auth.user.id,
      notify_email: email.trim() || null,
      notify_phone: phone.trim() || null,
      admin_id: adminId || null,
      updated_at: new Date().toISOString(),
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    setSaved(true);
    router.refresh();
  }

  return (
    <div className="terminal-panel p-6">
      <p className="section-kicker">// where alerts go</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">
        Notification preferences
      </p>
      <p className="mt-2 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
        The administrator you choose configures how alerts are actually
        delivered. You only say where they should land.
      </p>

      <form onSubmit={save} className="mt-6 grid gap-4 sm:grid-cols-2">
        <label className="block sm:col-span-1">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Notification email
          </span>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@example.com"
            className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
          />
        </label>

        <label className="block sm:col-span-1">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Phone number <span className="text-muted-foreground/70">(optional)</span>
          </span>
          <input
            type="tel"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder="+1 555 000 0000"
            className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
          />
        </label>

        <label className="block sm:col-span-2">
          <span className="mb-1.5 block font-mono text-[0.65rem] uppercase text-muted-foreground">
            Administrator
          </span>
          <select
            value={adminId}
            onChange={(event) => setAdminId(event.target.value)}
            className="w-full border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
          >
            <option value="">not chosen — alerts will not be delivered</option>
            {admins.map((a) => (
              <option key={a.id} value={a.id}>
                {a.full_name || a.email || a.id}
              </option>
            ))}
          </select>
          <span className="mt-1 block font-mono text-[0.65rem] leading-5 text-muted-foreground">
            Whoever you pick sees your machines and routes your alerts through
            the channels they have configured.
          </span>
        </label>

        {error ? (
          <p role="alert" className="sm:col-span-2 font-mono text-xs text-destructive">
            {error}
          </p>
        ) : null}
        {saved && !error ? (
          <p className="sm:col-span-2 font-mono text-xs text-primary">Saved.</p>
        ) : null}

        <div className="sm:col-span-2">
          <Button type="submit" size="sm" disabled={busy} className="gap-2">
            {busy ? <Loader2 className="size-4 animate-spin" /> : null}
            Save preferences
          </Button>
        </div>
      </form>
    </div>
  );
}
