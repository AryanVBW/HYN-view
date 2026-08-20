import Link from "next/link";
import { Logo } from "@/components/logo";
import { ParticleField } from "@/components/particle-field";

// Shared shell for the public policy pages. Typography is set here so they
// cannot drift apart visually.
export function LegalPage({
  title,
  kicker,
  updated,
  children,
}: {
  title: string;
  kicker: string;
  updated: string;
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background">
      <ParticleField blur="soft" />
      <main className="container pt-32 pb-16 md:pt-44">
        <div className="mx-auto max-w-3xl">
          <Link href="/" className="inline-block">
            <Logo className="w-[110px]" />
          </Link>

          <div className="mt-10 border-b border-border pb-8">
            <p className="section-kicker">{kicker}</p>
            <h1 className="mt-2 font-sentient text-3xl text-foreground md:text-4xl">
              {title}
            </h1>
            <p className="mt-3 font-mono text-xs text-muted-foreground">
              Last updated {updated}
            </p>
          </div>

          <div className="legal-prose mt-10">{children}</div>

          <nav className="mt-16 flex flex-wrap gap-x-6 gap-y-2 border-t border-border pt-8 font-mono text-xs text-muted-foreground">
            <Link href="/privacy" className="hover:text-primary">Privacy</Link>
            <Link href="/terms" className="hover:text-primary">Terms</Link>
            <Link href="/acceptable-use" className="hover:text-primary">Acceptable use</Link>
            <Link href="/security" className="hover:text-primary">Security</Link>
            <Link href="/subprocessors" className="hover:text-primary">Providers</Link>
            <Link href="/dpa" className="hover:text-primary">DPA</Link>
            <Link href="/legal" className="hover:text-primary">Disclaimer &amp; licence</Link>
            <Link href="/" className="hover:text-primary">Home</Link>
          </nav>
        </div>
      </main>
    </div>
  );
}

// A callout for the things a reader must not miss.
export function Important({ children }: { children: React.ReactNode }) {
  return (
    <div className="my-6 border-l-2 border-primary bg-primary/5 px-4 py-3 font-mono text-sm leading-7 text-foreground/80">
      {children}
    </div>
  );
}
