import Link from "next/link";
import { Radio, ServerOff, ShieldAlert, Terminal } from "lucide-react";
import { DemoDataButton } from "./demo-data-button";
import { RefreshButton } from "./refresh-button";

function CommandBlock({ lines }: { lines: string[] }) {
  return (
    <div className="mt-6 overflow-x-auto border border-border bg-foreground/[0.04] p-4">
      <pre className="font-mono text-xs leading-6 text-card-foreground">
        {lines.map((line) => (
          <span key={line} className="block">
            {line.startsWith("#") ? (
              <span className="text-muted-foreground">{line}</span>
            ) : (
              <>
                <span className="text-muted-foreground select-none">$ </span>
                <span className="text-primary">{line}</span>
              </>
            )}
          </span>
        ))}
      </pre>
    </div>
  );
}

// Shown when the account has no nodes at all. The instructions are the real
// ones, in the order they have to happen.
export function NoNodesState({ canDemo = false }: { canDemo?: boolean }) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-8 duration-500 md:p-12">
      <div className="mx-auto max-w-xl text-center">
        <ServerOff className="mx-auto size-10 text-muted-foreground" aria-hidden />
        <h2 className="mt-6 font-sentient text-2xl text-card-foreground md:text-3xl">
          No server is linked yet
        </h2>
        <p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">
          Link your Ubuntu server and it appears here immediately. No admin
          assignment is needed. Readings appear when the agent checks in.
        </p>
      </div>

      <div className="mx-auto mt-8 max-w-xl">
        <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
          on the server
        </p>
        <CommandBlock
          lines={[
            "npm install -g hyn-view",
            "sudo hyn link",
            "# prints a code like  4F2K-9QXZ",
          ]}
        />

        <p className="mt-6 font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
          then here, on this device
        </p>
        <Link href="/link" className="mt-3 inline-block font-mono text-sm text-primary underline underline-offset-4">
          Enter the pairing code →
        </Link>

        <p className="mt-6 font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
          finally, back on the server
        </p>
        <CommandBlock
          lines={["sudo hyn setup", "# checks settings every minute; reports every 10 minutes by default"]}
        />
      </div>

      {canDemo ? <div className="mx-auto mt-10 flex max-w-xl flex-col items-center gap-3 border-t border-border pt-8 text-center">
        <p className="font-mono text-xs leading-6 text-muted-foreground">
          Just looking around? Load a demo node with synthetic readings. It is
          labelled as demo everywhere and you can remove it in one click.
        </p>
        <DemoDataButton mode="seed" />
      </div> : null}
    </div>
  );
}

// Shown when the signed-in account's profile row isn't in the state the
// dashboard needs yet. Three distinct causes share this screen, so the copy
// and the action both change with the cause rather than dead-ending everyone
// on the same unfixable sentence.
export function DashboardAccessUnavailable({
  suspended,
  transient,
  detail,
}: {
  suspended: boolean;
  // True right after signup, before the profile row created by the auth
  // trigger has become visible to this request — a timing gap, not a fault.
  transient: boolean;
  // The store's own error, when there was one. Shown verbatim: "could not be
  // loaded" tells an operator nothing, and the underlying message is usually
  // the whole diagnosis.
  detail?: string | null;
}) {
  const heading = suspended
    ? "Your account is suspended"
    : transient
      ? "Setting up your account"
      : "Dashboard access unavailable";
  const body = suspended
    ? "A Super admin suspended this account, which pauses every server it owns along with it. Contact a Super admin to have it reinstated."
    : transient
      ? "Your account was just created and is still being provisioned. This usually clears in a few seconds — try refreshing."
      : "Ask a Super admin to finish the portal roles setup for this account, then refresh this page.";

  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-8 duration-500 md:p-12">
      <div className="mx-auto max-w-xl text-center">
        <ShieldAlert
          className={`mx-auto size-10 ${suspended ? "text-destructive" : "text-muted-foreground"}`}
          aria-hidden
        />
        <h1 className="mt-6 font-sentient text-2xl text-card-foreground md:text-3xl">
          {heading}
        </h1>
        <p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">
          {body}
        </p>
        {detail ? (
          <p className="mx-auto mt-4 max-w-md rounded-md border border-border/60 bg-card/60 p-3 font-mono text-xs leading-5 break-words text-muted-foreground">
            {detail}
          </p>
        ) : null}
        {!suspended ? (
          <div className="mt-8">
            <RefreshButton />
          </div>
        ) : null}
      </div>
    </div>
  );
}

// Shown when a node is paired but has not pushed yet. Distinct from "no node",
// because the fix is different: wait, or run the push by hand.
export function AwaitingFirstPushState({ nodeName }: { nodeName: string }) {
  return (
    <div className="terminal-panel animate-in fade-in slide-in-from-bottom-2 p-8 duration-500 md:p-12">
      <div className="mx-auto max-w-xl text-center">
        <Radio className="mx-auto size-10 animate-pulse text-primary" aria-hidden />
        <h2 className="mt-6 font-sentient text-2xl text-card-foreground md:text-3xl">
          {nodeName} is linked, but has not reported yet
        </h2>
        <p className="mt-3 font-mono text-sm leading-7 text-muted-foreground">
          Pairing worked. No metrics have arrived, so there is nothing to plot —
          rather than show you an empty chart, here is what to check.
        </p>
      </div>

      <div className="mx-auto mt-8 max-w-xl">
        <p className="font-mono text-[0.65rem] uppercase tracking-wide text-muted-foreground">
          on the server
        </p>
        <CommandBlock
          lines={[
            "hyn cloud status",
            "sudo hyn push",
            "# then install the timer so it keeps happening",
            "sudo hyn setup",
          ]}
        />
        <p className="mt-4 flex items-start gap-2 font-mono text-xs leading-6 text-muted-foreground">
          <Terminal className="mt-0.5 size-4 shrink-0" aria-hidden />
          <span>
            <code className="text-primary">hyn cloud status</code> prints when the last
            push happened and the error if it failed.
          </span>
        </p>
      </div>
    </div>
  );
}
