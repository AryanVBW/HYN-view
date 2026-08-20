"use client";

import { cn } from "@/lib/utils";
import * as Dialog from "@radix-ui/react-dialog";
import { Menu, X } from "lucide-react";
import Link from "next/link";
import { useState } from "react";

interface MobileMenuProps {
  className?: string;
  signedIn?: boolean;
  email?: string | null;
}

export const MobileMenu = ({ className, signedIn = false, email = null }: MobileMenuProps) => {
  const [isOpen, setIsOpen] = useState(false);

  const menuItems = [
    { name: "Dashboard", href: "/dashboard" },
    { name: "Link server", href: "/link" },
    signedIn
      ? { name: "My account", href: "/account" }
      : { name: "Sign in", href: "/signin" },
  ];

  const handleLinkClick = () => {
    setIsOpen(false);
  };

  return (
    <Dialog.Root modal={false} open={isOpen} onOpenChange={setIsOpen}>
      <Dialog.Trigger asChild>
        <button
          className={cn(
            "group lg:hidden p-2 text-foreground transition-colors",
            className
          )}
          aria-label="Open menu"
        >
          <Menu className="group-[[data-state=open]]:hidden" size={24} />
          <X className="hidden group-[[data-state=open]]:block" size={24} />
        </button>
      </Dialog.Trigger>

      <Dialog.Portal>
        <div
          data-overlay="true"
          className="fixed z-30 inset-0 bg-black/50 backdrop-blur-sm"
        />

        <Dialog.Content
          onInteractOutside={(e) => {
            if (
              e.target instanceof HTMLElement &&
              e.target.dataset.overlay !== "true"
            ) {
              e.preventDefault();
            }
          }}
          className="fixed top-0 left-0 w-full z-40 py-28 md:py-40"
        >
          <Dialog.Title className="sr-only">Menu</Dialog.Title>

          <nav className="flex flex-col space-y-6 container mx-auto">
            {menuItems.map((item) => (
              <Link
                key={item.name}
                href={item.href}
                onClick={handleLinkClick}
                className="text-xl font-mono uppercase text-foreground/60 transition-colors ease-out duration-150 hover:text-foreground/100 py-2"
              >
                {item.name}
                {item.href === "/account" && email ? (
                  <span className="mt-1 block text-xs normal-case text-muted-foreground">
                    {email}
                  </span>
                ) : null}
              </Link>
            ))}

            <div className="mt-6">
              <Link
                href="#contact"
                onClick={handleLinkClick}
                className="inline-block text-xl font-mono uppercase text-primary transition-colors ease-out duration-150 hover:text-primary/80 py-2"
              >
                GitHub
              </Link>
            </div>
          </nav>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
};
