import Link from "next/link";
import { Logo } from "@/components/logo";

// Shared shell for the legal pages. Typography is set here rather than per page
// so the three documents cannot drift apart visually.
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

export function Placeholder({ children }: { children: React.ReactNode }) {
  return (
    <span className="border border-dashed border-[#e8a400]/60 bg-[#e8a400]/10 px-1.5 py-0.5 font-mono text-[0.8em] text-[#e8a400]">
      {children}
    </span>
  );
}
