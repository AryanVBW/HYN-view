// Supabase connection values.
//
// Both of these are public by design: the anon key is shipped to every browser
// that loads this app, and Row Level Security (see supabase/schema.sql) is what
// actually protects the data. Never put the service-role key here — it bypasses
// RLS and would be readable by anyone who opens devtools.

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

// The portal is useful to look at before anyone has wired up a backend, so
// missing configuration is a state to render rather than a crash. Pages check
// this and show setup instructions instead of throwing at request time.
export const isSupabaseConfigured = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
