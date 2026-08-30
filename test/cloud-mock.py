"""Local PostgREST mock used by test/cloud-integration.sh."""

import base64
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


LOG = sys.argv[2]
state = {
    "polls": 0,
    "node_status": "active",
    "command_kind": None,
    "command_claimed": False,
    "config_override": {},
    "config_dropped": set(),
    # The resident agent's beat: counted so a test can prove one was sent, and
    # switchable so the pre-migration 404 fallback can be exercised.
    "beats": 0,
    "heartbeat_rpc": True,
}


def portal_config():
    """The settings the portal would return, plus the hostile ones the agent must
    refuse. /config/<key>/<value> and /config/drop/<key> let a test change or
    withdraw one, which is how the change-detection path is exercised."""
    config = {
        "alert_mem_pct": 80,
        "alert_disk_pct": "x[$(touch${IFS}$HYN_VAR/cloud-rce-marker)]",
        "report_at": "07:30",
        "auto_update": "install",
        "notify_access_details": "on",
        "webhook_url": "https://attacker.example/hook",
        "heartbeat_url": "https://attacker.example/ping",
        "notify_to": "attacker@example.com",
        "telegram_chat_id": "12345",
        "ntfy_topic": "attacker-topic",
        "cloud_url": "https://attacker.example",
        "interval": "2.0",
        "not_a_real_key": "x",
    }
    config.update(state["config_override"])
    for key in state["config_dropped"]:
        config.pop(key, None)
    return config


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        # Test-only lever to flip the node's administrative status.
        if self.path.startswith("/status/"):
            state["node_status"] = self.path.rsplit("/", 1)[-1]
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if self.path == "/command/clear":
            state["command_kind"] = None
            state["command_claimed"] = False
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        # Test-only lever: pretend to be a portal deployment that has not applied
        # the heartbeat migration, so the agent's fallback path is exercised.
        if self.path in ("/heartbeat/on", "/heartbeat/off"):
            state["heartbeat_rpc"] = self.path.endswith("/on")
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if self.path in ("/command/queue", "/command/sync"):
            state["command_kind"] = "sync" if self.path.endswith("/sync") else "update"
            state["command_claimed"] = False
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        # Test-only levers for portal-managed settings: change one, or withdraw
        # one so the agent falls back to its own default.
        #   /config/<key>/<value>   set it
        #   /config/drop/<key>      remove it
        if self.path.startswith("/config/"):
            parts = self.path.split("/")[2:]
            if len(parts) == 2 and parts[0] == "drop":
                state["config_override"].pop(parts[1], None)
                state["config_dropped"].add(parts[1])
            elif len(parts) == 2:
                state["config_override"][parts[0]] = parts[1]
                state["config_dropped"].discard(parts[0])
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode()
        with open(LOG, "a", encoding="utf-8") as log_file:
            log_file.write(
                json.dumps(
                    {
                        "path": self.path,
                        "headers": {key.lower(): value for key, value in self.headers.items()},
                        "body": raw,
                    }
                )
                + "\n"
            )

        function = self.path.rsplit("/", 1)[-1]
        if function == "hyn_device_start":
            output = {
                "user_code": "QKB8-D6VQ",
                "device_code": "a" * 64,
                "expires_at": "2026-08-19T13:00:00Z",
                "interval": 1,
            }
        elif function == "hyn_device_poll":
            state["polls"] += 1
            # Pending once, so the client's polling loop is genuinely exercised.
            if state["polls"] < 2:
                output = {"status": "pending", "interval": 1}
            else:
                output = {
                    "status": "approved",
                    "node_id": "3f7a0000-0000-4000-8000-000000000001",
                    "node_token": "b" * 64,
                    "node_name": "web-01",
                }
        elif function == "hyn_fetch_config":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            output = {
                "status": "ok",
                "node_id": "3f7a0000-0000-4000-8000-000000000001",
                "node_name": "web-01",
                "node_status": state["node_status"],
                "paused_until": None,
                "status_reason": None,
                "alert_template_b64": base64.b64encode(
                    b'<div data-template="alert">{{hostname}}|{{severity}}|{{subject}}|{{content}}</div>'
                ).decode(),
                "report_template_b64": base64.b64encode(
                    b'<div data-template="report">{{content}}</div>'
                ).decode(),
                "config": portal_config(),
                "channels": [
                    {
                        "kind": "resend",
                        "target": "ops@example.com",
                        "secret": "re_secret",
                        "extra": {},
                    }
                ],
            }
        elif function == "hyn_report_notification":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            output = {"status": "ok", "written": len(body.get("p_events") or [])}
        elif function == "hyn_claim_node_command":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            if not state["command_kind"] or state["command_claimed"]:
                output = {"status": "idle"}
            else:
                state["command_claimed"] = True
                output = {
                    "status": "command",
                    "id": "4f8b0000-0000-4000-8000-000000000002",
                    "action": state["command_kind"],
                    "stage": "accepted",
                }
        elif function == "hyn_report_node_command":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            if body.get("p_command_id") != "4f8b0000-0000-4000-8000-000000000002":
                self._error(400, "unknown command")
                return
            output = {"status": body.get("p_status"), "stage": body.get("p_stage")}
        elif function == "hyn_queue_web_notification":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            event = body.get("p_event") or {}
            if any(key in event for key in ("recipient", "to", "from", "sender", "email")):
                self._error(400, "web event cannot select a recipient or sender")
                return
            output = {
                "status": "queued",
                "id": "5f8c0000-0000-4000-8000-000000000003",
                "created": True,
                "fingerprint": event.get("fingerprint"),
            }
        elif function == "hyn_heartbeat":
            # The resident agent's beat. Deliberately the cheapest branch here,
            # mirroring the real RPC: a token check and a status, no config, no
            # templates. `/heartbeat/off` makes it 404 so the agent's fallback to
            # the settings pull can be exercised against a portal that predates
            # this function.
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            if not state.get("heartbeat_rpc", True):
                self._error(404, "no such function")
                return
            state["beats"] = state.get("beats", 0) + 1
            output = {
                "status": "ok",
                "node_id": "3f7a0000-0000-4000-8000-000000000001",
                "node_status": state["node_status"],
                "heartbeat_at": "2026-08-30T12:00:00Z",
            }
        elif function == "hyn_ingest":
            body = json.loads(raw)
            if body.get("p_node_token") != "b" * 64:
                self._error(401, "invalid node token")
                return
            if state["node_status"] == "paused":
                self._error(400, "node paused until 2026-08-19T18:00:00Z")
                return
            if state["node_status"] == "suspended":
                self._error(400, "node suspended: abuse investigation")
                return
            output = {
                "status": "ok",
                "node_id": "3f7a0000-0000-4000-8000-000000000001",
            }
        else:
            self._error(404, "no such function")
            return

        payload = json.dumps(output).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _error(self, status, message):
        payload = json.dumps({"message": message}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
