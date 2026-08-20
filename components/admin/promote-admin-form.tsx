"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

// "Add another admin" for someone who already has an account: promoting by
// role toggle in the client table works once they show up there, but this is
// the direct path when you already know their email. Someone with no account
// yet has no profile row to promote -- hyn_admin_promote_by_email reports
// that as not_found rather than inventing a pending invite system nobody asked
// for; ask them to sign in once, then promote.
export function PromoteAdminForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: "ok" | "bad"; text: string } | null>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email.trim()) return;
    setBusy(true);
    setMessage(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("hyn_admin_promote_by_email", {
      p_email: email.trim(),
    });
    setBusy(false);
    if (error) {
      setMessage({ tone: "bad", text: error.message });
      return;
    }
    if (data?.status === "not_found") {
      setMessage({
        tone: "bad",
        text: "No account with that email yet. Ask them to sign in once, then try again.",
      });
      return;
    }
    setMessage({ tone: "ok", text: `${email.trim()} is now an administrator.` });
    setEmail("");
    router.refresh();
  }

  return (
    <div className="terminal-panel p-6">
      <p className="section-kicker">// add another admin</p>
      <p className="mt-2 font-sentient text-2xl text-card-foreground">
        Promote by email
      </p>
      <p className="mt-2 max-w-xl font-mono text-xs leading-6 text-muted-foreground">
        Grants full administrator access: every client, every machine, and the
        ability to promote or suspend others. They must have signed in at least
        once.
      </p>
      <form onSubmit={submit} className="mt-6 flex flex-wrap gap-3">
        <input
          type="email"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="colleague@example.com"
          className="min-w-0 flex-1 border border-input bg-background px-3 py-2.5 font-mono text-sm text-foreground outline-none focus:border-ring"
        />
        <Button type="submit" size="sm" disabled={busy} className="gap-2">
          {busy ? <Loader2 className="size-4 animate-spin" /> : <UserPlus className="size-4" />}
          Make administrator
        </Button>
      </form>
      {message ? (
        <p
          role="status"
          className={`mt-4 font-mono text-xs ${message.tone === "ok" ? "text-primary" : "text-destructive"}`}
        >
          {message.text}
        </p>
      ) : null}
    </div>
  );
}
