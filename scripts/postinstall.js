#!/usr/bin/env node
// Prints next steps after `npm i -g hyn-view`.
//
// Deliberately does nothing else. A postinstall script runs with whatever
// privilege npm had, which for a global install is often root -- writing
// systemd units or touching /etc from here would be doing privileged work the
// user did not ask for. That belongs in `sudo hyn setup`, which is explicit.

const { chmodSync, existsSync } = require('node:fs');
const { join } = require('node:path');
const os = require('node:os');

const root = join(__dirname, '..');
const bin = join(root, 'bin', 'hyn');

// npm normally sets the exec bit on files listed in "bin", but not when the
// package is consumed as a plain directory dependency or a git checkout.
try {
  if (existsSync(bin)) chmodSync(bin, 0o755);
} catch {
  /* not fatal: the shebang still works via `bash bin/hyn` */
}

if (process.env.npm_config_loglevel === 'silent' || process.env.CI) process.exit(0);

const c = process.stdout.isTTY
  ? { d: '\x1b[2m', a: '\x1b[36m', b: '\x1b[1m', r: '\x1b[0m' }
  : { d: '', a: '', b: '', r: '' };

const lines = [
  '',
  `${c.a}${c.b}hyn-view${c.r} installed.`,
  '',
  `  ${c.b}hyn${c.r}                  open the dashboard`,
  `  ${c.b}sudo hyn setup${c.r}       install /etc config + scheduled speed tests`,
  `  ${c.b}hyn doctor${c.r}           check this machine`,
  `  ${c.b}hyn help${c.r}             everything else`,
  '',
];

if (os.platform() !== 'linux') {
  lines.push(
    `${c.d}Note: hyn reads /proc and /sys directly, so it only runs on Linux.`,
    `Installed here for packaging or development purposes only.${c.r}`,
    ''
  );
}

process.stdout.write(lines.join('\n') + '\n');
