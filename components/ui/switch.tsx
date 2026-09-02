"use client";

import * as React from "react";
import * as SwitchPrimitive from "@radix-ui/react-switch";

import { cn } from "@/lib/utils";

// The shadcn-style wrapper this project's own button.tsx/badge.tsx pattern
// implies but never had: @radix-ui/react-switch has been an installed
// dependency the whole time (package.json), so the hand-rolled
// role="switch" button in email-preferences.tsx was a one-off standing in
// for a component that was already a dependency away -- exactly the
// "missing token/component, not a design gap" case. Colours come from this
// project's own tokens (--primary, --border, --input), not shadcn's
// defaults, so it reads as this product's switch rather than an imported one.
function Switch({
  className,
  ...props
}: React.ComponentProps<typeof SwitchPrimitive.Root>) {
  return (
    <SwitchPrimitive.Root
      data-slot="switch"
      className={cn(
        "peer inline-flex h-6 w-11 shrink-0 items-center rounded-full border shadow-xs transition-all outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50",
        "data-[state=checked]:border-primary data-[state=checked]:bg-primary/20 data-[state=unchecked]:border-input data-[state=unchecked]:bg-muted",
        className
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb
        data-slot="switch-thumb"
        className={cn(
          "pointer-events-none block size-4 rounded-full ring-0 transition-transform data-[state=checked]:translate-x-5 data-[state=checked]:bg-primary data-[state=checked]:shadow-[0_0_6px_var(--primary)] data-[state=unchecked]:translate-x-0.5 data-[state=unchecked]:bg-foreground"
        )}
      />
    </SwitchPrimitive.Root>
  );
}

export { Switch };
