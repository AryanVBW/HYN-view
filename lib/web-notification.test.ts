import assert from "node:assert/strict";
import test from "node:test";
import { dispatchWebNotificationJob } from "./web-notification.ts";

test("one durable alert fingerprint sends once even when dispatch is retried", async () => {
  let claimed = false;
  let sends = 0;
  const completed: string[] = [];
  const dependencies = {
    claim: async () => {
      if (claimed) return null;
      claimed = true;
      return {
        id: "job-1",
        nodeId: "node-1",
        nodeName: "relay-01",
        hostname: "relay-01.local",
        recipient: "owner@example.com",
        fingerprint: "disk:warn:86",
        category: "alert" as const,
        severity: "warn" as const,
        subject: "Disk warning",
        textBody: "Disk is 86% full",
        htmlBody: "<p>Disk is 86% full</p>",
      };
    },
    send: async () => {
      sends += 1;
      return { ok: true as const, providerId: "email-1" };
    },
    complete: async (_jobId: string, status: "sent" | "failed") => {
      completed.push(status);
    },
  };

  assert.equal((await dispatchWebNotificationJob("job-1", dependencies)).status, "sent");
  assert.equal((await dispatchWebNotificationJob("job-1", dependencies)).status, "idle");
  assert.equal(sends, 1);
  assert.deepEqual(completed, ["sent"]);
});
