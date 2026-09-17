interface D1Meta {
  changes?: number;
}

interface D1Result<T = unknown> {
  results: T[];
  meta: D1Meta;
  success: boolean;
}

interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  first<T = unknown>(): Promise<T | null>;
  run(): Promise<D1Result>;
  all<T = unknown>(): Promise<D1Result<T>>;
}

interface D1Database {
  prepare(query: string): D1PreparedStatement;
  batch<T = unknown>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]>;
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}

interface ScheduledEvent {
  cron: string;
}

interface ExportedHandler<Env = unknown> {
  fetch?: (request: Request, env: Env, ctx: ExecutionContext) => Response | Promise<Response>;
  scheduled?: (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => void | Promise<void>;
}

interface Env {
  DB: D1Database;
  SUPABASE_JWT_SECRET?: string;
  SUPABASE_URL?: string;
  SUPABASE_JWT_ISS?: string;
  PAIRING_PEPPER?: string;
  DATA_SERVICE_KEY?: string;
  BOOTSTRAP_EMAIL?: string;
}
