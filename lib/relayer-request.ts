import type { Relayer } from "./relayer.ts";

export function requestedRelayer(fleet: Relayer[], input: string): Relayer {
  const query = input.trim().replace(/^#(?=\d+$)/, "");
  if (!query || query.length > 100)
    throw new Error("Enter your Highway name or numeric relayer ID.");
  const matches = fleet.filter((r) =>
    /^\d+$/.test(query)
      ? r.id === Number(query)
      : r.name.toLowerCase() === query.toLowerCase(),
  );
  if (!matches.length)
    throw new Error(
      "Relayer not found. Use the exact Highway name or numeric ID.",
    );
  if (matches.length > 1)
    throw new Error(
      "Several relayers have that name. Use the numeric relayer ID.",
    );
  return matches[0];
}
