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
vm.runInNewContext(src, { module, console, Date, Math, JSON, String })
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
eq(M.localCommand('/p/s.sh', 2), ['/bin/sh', '/p/s.sh', '2', '', 'cpu'], 'local command')
const rc = M.remoteCommand('/p/s.sh', 'studio-mini', 2)
eq(rc.slice(0, 6), ['/bin/sh', '-c', 'f=$1; d=$2; shift 2; [ -z "$d" ] || mkdir -p -m 700 "$d"; exec ssh "$@" < "$f"', 'vitals-ssh', '/p/s.sh', ''], 'remote wrapper redirects the sampler into ssh')
ok(!rc.includes('ControlMaster=auto'), 'no control socket without a runtime directory')
const rcc = M.remoteCommand('/p/s.sh', 'studio-mini', 2, '', 'cpu', '/run/user/1000/vitals-ssh')
ok(rcc.includes('ControlMaster=auto') && rcc.includes('ControlPath=/run/user/1000/vitals-ssh/%C') && rcc.includes('ControlPersist=no'), 'card sessions share a private control socket')
eq(rcc[5], '/run/user/1000/vitals-ssh', 'the wrapper is told which directory to create')
ok(rc.includes('BatchMode=yes') && rc.includes('ConnectTimeout=8') && rc.includes('ServerAliveInterval=10') && rc.includes('ServerAliveCountMax=2'), 'ssh options present')
eq(rc.slice(rc.indexOf('--')), ['--', 'studio-mini', 'sh', '-s', '--', '2', '-', 'cpu'], 'destination follows -- and the remote runs sh -s')
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
eq(M.parseLine('{"type":"renew"}'), { type: 'renew' }, 'renewal line parsed')
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

// ---- version 2: per-machine readouts
const v1 = '{ "version": 1, "machines": [ { "id": "local", "alias": "", "host": "", "enabled": true }, { "id": "studio-mini", "alias": "studio-mini", "host": "studio-mini" } ] }'
const p1 = M.parseMachinesFile(v1)
eq([p1.ok, p1.version], [true, 1], 'a version 1 file parses and reports its version')
eq(M.machineModules(p1.machines[1], ['cpu', 'memory', 'network']), ['cpu', 'memory', 'network'], 'a v1 machine follows the default modules')
const v2text = M.serializeMachines(p1.machines)
eq(JSON.parse(v2text).version, 2, 'serializing writes version 2')
eq(JSON.parse(v2text).machines[1], { id: 'studio-mini', alias: 'studio-mini', host: 'studio-mini', enabled: true }, 'migration adds nothing a machine did not set')
let mm = M.updateMachine(p1.machines, 'studio-mini', { modules: ['gpu', 'cpu', 'bogus', 'gpu'], styles: { cpu: 'ring-text', network: 'nonsense' }, disks: [{ disk: 'all', show: 'used' }, { disk: 'bad name' }], sensors: ['cpu', 'nvme/temp1', 'x"y'], gpus: 'all' })
const sm = mm[1]
eq(sm.modules, ['gpu', 'cpu'], 'modules are deduped and filtered')
eq(sm.styles, { cpu: 'ring-text' }, 'invalid looks dropped')
eq(sm.disks, [{ disk: 'all', show: 'used' }], 'invalid disk names dropped')
eq(sm.sensors, ['cpu', 'nvme/temp1'], 'invalid sensor ids dropped')
eq(M.parseMachinesFile(M.serializeMachines(mm)).machines[1], sm, 'v2 round trip keeps readout settings')
mm = M.upsertMachine(mm, { id: 'studio-mini', alias: 'studio', host: 'me@studio-mini' }).machines
eq(mm[1].modules, ['gpu', 'cpu'], 'renaming keeps readout settings')
eq(M.resetReadouts(mm, 'studio-mini')[1], { id: 'studio-mini', alias: 'studio', host: 'me@studio-mini', enabled: true }, 'reset clears readout settings')
eq(M.updateMachine(mm, 'studio-mini', { modules: null })[1].modules, undefined, 'null goes back to the default')

eq(M.parseModules('mem, net ,disk,bogus,cpu'), ['memory', 'network', 'disks', 'cpu'], 'module aliases')
eq(M.fitStyle('network', 'ring'), 'graph', 'network has no ring')
eq(M.fitStyle('sensors', 'both'), 'text', 'sensors are figures only')
eq(M.fitStyle('battery', 'both'), 'ring-text', 'battery has a ring but no graph')
eq(M.fitStyle('disks', 'ring-text'), 'both', 'disk looks fold to picture/figure')
eq(M.styleOptions('network').map(o => o.value), ['graph', 'text', 'both'], 'network look choices')
eq(M.machineStyle({ styles: { cpu: 'ring' } }, 'cpu', 'both'), 'ring', 'per-machine look wins')
eq(M.machineStyle({}, 'memory', 'text'), 'text', 'global default look applies')

const macInfo = { os: 'macos', caps: { gpu: true, disks: true, sensors: false, battery: false }, gpus: [{ id: 'apple', vendor: 'apple' }], sensors: [] }
eq(M.moduleAvailable('battery', macInfo), false, 'no battery on a desktop Mac')
eq(M.unavailableReason('sensors', macInfo), 'No sensors found', 'macOS sensors reason')
eq(M.moduleAvailable('battery', {}), true, 'before the first hello every module is offered')
const ro = M.readouts({ modules: ['cpu', 'battery', 'gpu', 'disks', 'sensors'], disks: [{ disk: 'all', show: 'speed' }, { disk: 'nvme0n1', show: 'used' }], showGpuMemory: true }, macInfo, null, 'both')
eq(ro.map(r => r.key), ['cpu', 'gpu:apple', 'vram:apple', 'disk:all', 'disk:nvme0n1'], 'readouts skip what the machine lacks and expand disks and GPUs')
eq(ro[3].label + ro[4].label, 'DSKNV0', 'several disks get short tags')
eq(M.samplerExtras({ modules: ['network', 'battery', 'cpu', 'gpu'] }), 'gpu,battery', 'only the costly modules go to the sampler')
eq(M.samplerExtras({}, ['cpu', 'memory', 'network']), '', 'defaults cost nothing extra')
eq(M.machineSensors({}, { sensors: [{ id: 'nvme/temp1' }, { id: 'battery' }] }), ['battery'], 'default sensor prefers cpu or battery')
eq(M.localCommand('/s', 2, 'gpu,disks', 'cpu,nvme/temp1'), ['/bin/sh', '/s', '2', 'gpu,disks', 'cpu,nvme/temp1'], 'local command carries extras and sensors')
const rc2 = M.remoteCommand('/s', 'build-box', 2, '', 'cpu')
eq(rc2.slice(-6), ['sh', '-s', '--', '2', '-', 'cpu'], 'remote command keeps an empty extras slot')

const hello = M.parseLine(JSON.stringify({ type: 'hello', v: 2, os: 'linux', cores: 8, caps: { gpu: true, disks: true, sensors: true, battery: false }, gpus: [{ id: '0000:03:00.0', name: 'AMD GPU', vendor: 'amd', util: true }], disks: ['nvme0n1'], sensors: [{ id: 'cpu', label: 'CPU temperature', kind: 'temp' }, { id: 'dell_smm/fan1', label: 'Dell fan1', kind: 'fan' }] }))
eq(hello.caps, { gpu: true, disks: true, sensors: true, battery: false }, 'hello capabilities')
eq(M.parseLine('{"type":"hello","os":"linux","cores":4}').caps, null, 'a version 1 hello has no capabilities')
const smp = M.parseLine(JSON.stringify({ type: 'sample', cpu: 5, memUsed: 1, memTotal: 2, gpus: [{ id: '0000:03:00.0', util: 40, mhz: null, temp: 51.5, memUsed: 1024, memTotal: 4096 }], disk: { read: 100, write: 50, per: { nvme0n1: [100, 50] }, space: { all: [25, 100] } }, temps: { cpu: 47.5 }, fans: { 'dell_smm/fan1': 0 }, battery: { percent: 80, status: 'Discharging', toEmpty: 95, toFull: null } }))
eq(M.gpuSample(smp, '0000:03:00.0').util, 40, 'gpu sample')
eq(M.diskRates(smp, 'nvme0n1'), [100, 50], 'per-disk rates')
eq(M.diskSpace(smp, 'all'), [25, 100], 'disk space')
eq(M.sensorReading(smp, hello, 'cpu', 'Celsius').text, '48°', 'temperature reading')
eq(M.sensorReading(smp, hello, 'cpu', 'Fahrenheit').text, '118°', 'fahrenheit')
eq(M.sensorReading(smp, hello, 'dell_smm/fan1', 'Celsius').text, 'off', 'a stopped fan reads off')
eq(M.sensorReading(smp, hello, 'nvme/temp1', 'Celsius'), null, 'an unreported sensor shows nothing')
eq(smp.battery.toEmpty, 95, 'battery time to empty')
let hh = M.pushSample(M.emptyHistory(), smp, 10)
hh = M.pushSample(hh, smp, 10)
eq([hh.gpu['0000:03:00.0'].length, hh.gpuMem['0000:03:00.0'][0], hh.diskRead.nvme0n1.length, hh.battery.length], [2, 25, 2, 2], 'histories for gpu, vram, disks and battery')
eq(M.trimHistory(hh, 1).diskWrite.all.length, 1, 'keyed histories trimmed')

// ---- detail panel
eq(M.detailCommand('/d.sh', '', 2, 'memory', false), ['/bin/sh', '/d.sh', '2', 'memory', '-'], 'local detail command')
const dc = M.detailCommand('/d.sh', 'studio-mini', 2, 'network', true, '/run/x')
eq(dc.slice(-3), ['2', 'network', 'all'], 'remote detail command carries tab and process level')
ok(dc.includes('ControlPath=/run/x/%C'), 'detail session rides the shared connection')
eq(M.detailTabs({ caps: { gpu: false, disks: true, sensors: false, battery: false } }), ['cpu', 'memory', 'disks', 'network'], 'tabs only for what a desktop Mac reports')
eq(M.detailTabs({ caps: { gpu: true, disks: true, sensors: true, battery: true } }), ['cpu', 'gpu', 'memory', 'disks', 'network', 'sensors', 'battery'], 'every tab on a laptop that has everything')
eq(M.detailTabs({}), ['cpu', 'gpu', 'memory', 'disks', 'network', 'sensors', 'battery'], 'before the first hello every tab is offered')
eq([M.tabFor('gpuMemory'), M.tabFor('disks'), M.tabFor('bogus')], ['gpu', 'disks', 'cpu'], 'readouts map to tabs')

console.log('# ' + n + ' passed')
JS
