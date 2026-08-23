export type ScheduleInterval = (callback: () => void, delay: number) => unknown;
export type ClearInterval = (token: unknown) => void;

export function startRecurringRefresh(
  refresh: () => void,
  schedule: ScheduleInterval = (callback, delay) => setInterval(callback, delay),
  clear: ClearInterval = (token) => clearInterval(token as ReturnType<typeof setInterval>),
  delay = 60_000,
) {
  const timer = schedule(refresh, delay);
  return () => clear(timer);
}
