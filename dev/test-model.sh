#!/bin/bash
#
# Unit tests for Model.js under Node (no compositor needed).

set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v node >/dev/null || { echo "test-model.sh: node is required" >&2; exit 1; }

REPO="$repo" node <<'JS'
const fs = require('fs')
const path = require('path')
const vm = require('vm')
// QML's `.pragma library` line is not JavaScript; drop it and load as CommonJS.
const src = fs.readFileSync(path.join(process.env.REPO, 'Model.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
const module = { exports: {} }
vm.runInNewContext(src, { module, console, Date, Math, JSON })
const M = module.exports

let n = 0
const ok = (cond, msg) => { if (!cond) { console.error('not ok - ' + msg); process.exit(1) } ; n++; console.log('ok - ' + msg) }
const eq = (a, b, msg) => ok(JSON.stringify(a) === JSON.stringify(b), msg + ' (got ' + JSON.stringify(a) + ')')

// settings
eq(M.resolveSettings({}).mode, 'dock', 'mode defaults to dock')
eq(M.resolveSettings({ mode: 'window' }).mode, 'window', 'window mode is accepted')
eq(M.resolveSettings({ mode: 'floating' }).mode, 'dock', 'unknown mode falls back to dock')
eq(M.resolveSettings({ width: 9999 }).width, 360, 'width is clamped')
eq(M.resolveSettings({ refreshSeconds: '5' }).refreshSeconds, 5, 'refresh enum string becomes a number')
eq(M.resolveSettings({ screen: '' }).screen, '', 'empty screen stays empty')
eq(M.historyLength(120, 2), 60, 'history length covers the window')

// machines
const fresh = M.normalizeMachines(null)
eq(fresh, [{ id: 'local', alias: '', host: '', enabled: true }], 'first run is just the local machine')
const messy = M.normalizeMachines({ machines: [
  { alias: 'studio', host: 'studio-mini' },
  { id: 'local', alias: 'my laptop' },
  { id: 'local', alias: 'second local' },
  { alias: 'bad', host: '-oProxyCommand=evil' },
  { alias: 'dup', host: 'studio-mini', id: 'studio' },
  { id: 'studio', alias: 'again', host: 'user@100.64.0.1', enabled: false },
  'junk', null
] })
eq(messy.map(m => m.id), ['studio', 'local', 'dup', 'again'], 'one local, unique ids, invalid hosts dropped')
eq(messy[1].alias, 'my laptop', 'local alias kept')
eq(messy[3].enabled, false, 'enabled flag kept')
ok(M.normalizeMachines({ machines: [{ alias: 'x', host: 'x' }] })[0].id === 'local', 'a missing local entry is added first')

ok(M.validateHost('') !== '', 'empty host rejected')
ok(M.validateHost('-oProxyCommand=x') !== '', 'leading dash rejected')
ok(M.validateHost('a b') !== '', 'whitespace rejected')
ok(M.validateHost('host;rm') !== '', 'shell characters rejected')
eq(M.validateHost('user@100.101.102.103'), '', 'user@ip accepted')
eq(M.validateHost('nas.example-tailnet.ts.net'), '', 'MagicDNS name accepted')
eq(M.validateHost('ssh://me@build-box:2222'), '', 'ssh URI accepted')

let r = M.upsertMachine(fresh, { id: '', alias: '', host: 'build-box' })
eq(r.error, '', 'adding a machine works')
eq(r.machines[1], { id: 'build-box', alias: 'build-box', host: 'build-box', enabled: true }, 'alias defaults to the destination')
r = M.upsertMachine(r.machines, { id: 'build-box', alias: 'builder', host: 'me@build-box' })
eq(r.machines[1].alias + '|' + r.machines[1].host, 'builder|me@build-box', 'editing keeps the id')
r = M.upsertMachine(r.machines, { id: 'local', alias: 'laptop', host: 'ignored' })
eq(r.machines[0], { id: 'local', alias: 'laptop', host: '', enabled: true }, 'local can be renamed but never gets a host')
eq(M.upsertMachine(fresh, { host: 'bad host' }).error !== '', true, 'invalid destination is refused')
eq(M.moveMachine(r.machines, 'build-box', -1).map(m => m.id), ['build-box', 'local'], 'move up')
eq(M.moveMachine(r.machines, 'local', -1).map(m => m.id), ['local', 'build-box'], 'move past the top is a no-op')
eq(M.removeMachine(r.machines, 'local').length, 2, 'local cannot be removed')
eq(M.removeMachine(r.machines, 'build-box').length, 1, 'remote can be removed')
eq(M.setMachineEnabled(r.machines, 'build-box', false)[1].enabled, false, 'toggle off')
const round = M.parseMachinesFile(M.serializeMachines(r.machines))
eq(round.machines, r.machines, 'serialize/parse round trip')
eq(M.parseMachinesFile('{ nope').ok, false, 'invalid JSON is reported, not thrown')
eq(M.displayAlias({ id: 'local', alias: '' }, 'studio.local'), 'studio', 'local alias falls back to the short hostname')

// commands
eq(M.localCommand('/p/s.sh', 2), ['/bin/sh', '/p/s.sh', '2'], 'local command')
const rc = M.remoteCommand('/p/s.sh', 'studio-mini', 2)
eq(rc.slice(0, 5), ['/bin/sh', '-c', 'f=$1; shift; exec ssh "$@" < "$f"', 'vitals-ssh', '/p/s.sh'], 'remote wrapper redirects the sampler into ssh')
ok(rc.includes('BatchMode=yes') && rc.includes('ConnectTimeout=8') && rc.includes('ServerAliveInterval=10') && rc.includes('ServerAliveCountMax=2'), 'ssh options present')
eq(rc.slice(rc.indexOf('--')), ['--', 'studio-mini', 'sh', '-s', '--', '2'], 'destination follows -- and the remote runs sh -s')
eq([1, 2, 3, 4, 5, 6, 9].map(M.backoffMs), [2000, 4000, 8000, 16000, 30000, 30000, 30000], 'backoff doubles up to 30 s')
eq(M.staleAfterMs(2), 8000, 'stale floor')
eq(M.staleAfterMs(10), 30000, 'stale scales with interval')

// samples
eq(M.parseLine('{"type":"hello","os":"macos","osName":"macOS 15","host":"studio","cores":10}').os, 'macos', 'hello parsed')
const s = M.parseLine('{"type":"sample","cpu":12.5,"user":8,"sys":4.5,"memUsed":8,"memTotal":16,"rx":100,"tx":50,"load":0.5}')
eq([s.cpu, s.memPercent, s.rx], [12.5, 50, 100], 'sample parsed')
eq(M.parseLine('{"type":"sample","cpu":250,"memUsed":99,"memTotal":10}').cpu, 100, 'cpu clamped')
eq(M.parseLine('{"type":"sample","cpu":250,"memUsed":99,"memTotal":10}').memUsed, 10, 'used clamped to total')
eq(M.parseLine('Welcome to the server!'), null, 'banner lines ignored')
eq(M.parseLine('{bad json'), null, 'broken json ignored')
let h = M.emptyHistory()
for (let i = 0; i < 10; i++) h = M.pushSample(h, s, 4)
eq(h.cpuUser.length, 4, 'history capped')
eq(M.trimHistory(h, 2).rx.length, 2, 'history trimmed')

// ssh reasons
eq(M.sshReason('ssh: Could not resolve hostname nope: Name or service not known'), 'Host not found', 'dns failure')
eq(M.sshReason('ssh: connect to host 10.0.0.9 port 22: Connection timed out'), 'Connection timed out', 'timeout')
eq(M.sshReason('user@host: Permission denied (publickey).'), 'SSH key not accepted', 'auth failure')
eq(M.sshReason('Host key verification failed.'), 'Host key not trusted yet', 'unknown host key')
eq(M.sshReason('/usr/bin/bash: line 1: cloudflared: command not found'), 'cloudflared: command not found', 'ProxyCommand shell prefix dropped')
eq(M.sshReason('/usr/bin/bash: line 1: 4242 Terminated cloudflared access ssh'), '', 'signal noise ignored')

// formatting
eq(M.compactRate(100), '0', 'tiny rates read 0')
eq(M.compactRate(34 * 1024), '34K', 'compact KB')
eq(M.compactRate(1.25 * 1024 * 1024), '1.3M', 'compact MB')
const GB = 1024 ** 3
eq(M.compactPair(18.3 * GB, 32 * GB), '18/32G', 'memory pair rounds from 10 up')
eq(M.compactPair(3.14 * GB, 8 * GB), '3.1/8G', 'memory pair keeps a decimal below 10')
eq(M.compactPair(412 * 1024 ** 2, 8 * GB), '412M/8G', 'mixed units')
eq(M.percentText(57.4), '57%', 'percent')

console.log('# ' + n + ' passed')
JS
