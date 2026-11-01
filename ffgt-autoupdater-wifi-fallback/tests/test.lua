-- Run from the package directory: lua5.1 tests/test.lua
package.path = './luasrc/usr/lib/lua/?.lua;' .. package.path
local core = require 'ffgt-wifi-fallback.core'
local total = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	assert(ok, name .. ': ' .. tostring(err))
	total = total + 1
	print('PASS ' .. name)
end
local function net(ssid, bssid)
	return {ssid = ssid or 'Freifunk', bssid = bssid or '00:11:22:33:44:55',
		mode = 'Master', encryption = {enabled = false}, phy = 'phy0'}
end
local function ready()
	return {up = true, ['ipv6-address'] = {{address = '2001:db8::123'}},
		route = {{target = '::', mask = 0}}, ['dns-server'] = {'2001:db8::53'}}
end

test('SSID case and surrounding text', function()
	for _, s in ipairs({'Freifunk', 'xFREIFUNKx', 'fReIfUnK Test'}) do assert(core.eligible(net(s))) end
	assert(not core.eligible(net('Other WLAN')))
end)
test('Open APs only', function()
	local n = net(); n.encryption.enabled = true; assert(not core.eligible(n))
	n.encryption = nil; assert(not core.eligible(n))
	n = net(); n.mode = 'Ad-Hoc'; assert(not core.eligible(n))
end)
test('Malformed SSID or BSSID rejected', function()
	assert(not core.eligible(net('Freifunk\0x')))
	assert(not core.eligible(net('Freifunk' .. string.rep('x', 32))))
	assert(not core.eligible(net('Freifunk', 'not-a-mac')))
end)
test('SSID punctuation accepted as data', function()
	assert(core.eligible(net("Freifunk ';&$()\\ Test")))
end)
test('IPv6 address route and DNS required', function()
	assert(core.ipv6_ready(ready()))
	for _, key in ipairs({'ipv6-address', 'route', 'dns-server'}) do
		local s = ready(); s[key] = {}; assert(not core.ipv6_ready(s))
	end
	assert(not core.ipv6_ready(nil))
end)
test('Link-local insufficient; ULA accepted', function()
	local s = ready(); s['ipv6-address'][1].address = 'fe80::1'; assert(not core.ipv6_ready(s))
	s['ipv6-address'][1].address = 'fd00::1'; assert(core.ipv6_ready(s))
	s.up = false; assert(not core.ipv6_ready(s))
end)
local function ops()
	local calls = {}; local o = {calls = calls}
	for _, k in ipairs({'down', 'stop', 'up', 'connect', 'ready'}) do
		o[k] = function() calls[#calls + 1] = k; return true end
	end
	o.update = function(branch) assert(branch == 'stable'); calls[#calls + 1] = 'update'; return 0 end
	o.cancelled = function() return false end
	o.upgrading = function() return false end
	o.log = function() end
	return o
end
local function count(list, key)
	local n = 0; for _, x in ipairs(list) do if x == key then n = n + 1 end end; return n
end
test('Every BSSID tried even after exit zero', function()
	local o = ops(); assert(core.round(o, {net(), net('Freifunk', '00:11:22:33:44:56')}, 'stable'))
	assert(count(o.calls, 'update') == 2 and count(o.calls, 'up') == 1)
	assert(o.calls[#o.calls] == 'up' and o.calls[#o.calls - 1] == 'stop')
end)
test('Connection failure skips updater', function()
	local o = ops(); o.connect = function() return false end
	assert(core.round(o, {net()}, 'stable')); assert(count(o.calls, 'update') == 0)
end)
test('No IPv6 skips updater', function()
	local o = ops(); o.ready = function() return false end
	assert(core.round(o, {net()}, 'stable')); assert(count(o.calls, 'update') == 0)
end)
test('Exception restores WiFi', function()
	local o = ops(); o.connect = function() error('driver failed') end
	assert(not core.round(o, {net()}, 'stable')); assert(o.calls[#o.calls] == 'up')
end)
test('Failed down still restores WiFi', function()
	local o = ops(); o.down = function() return false end
	assert(not core.round(o, {net()}, 'stable')); assert(o.calls[#o.calls] == 'up')
end)
test('Cleanup exception does not prevent wifi up', function()
	local o = ops(); o.stop = function() error('stop failed') end
	assert(not core.round(o, {net()}, 'stable')); assert(o.calls[#o.calls] == 'up')
end)
test('No candidates leaves WiFi untouched', function()
	local o = ops(); assert(core.round(o, {}, 'stable')); assert(#o.calls == 0)
end)
test('Cancellation restores without another candidate', function()
	local o = ops(); o.cancelled = function() return true end
	assert(core.round(o, {net()}, 'stable')); assert(count(o.calls, 'connect') == 0)
end)

test('Upgrade handoff prevents next AP and network cleanup', function()
 local o = ops(); local upgrading = false
 o.upgrading = function()return upgrading end
 o.update = function()upgrading = true; return 0 end
 assert(core.round(o, {net(), net()}, 'stable'))
 assert(count(o.calls, 'connect') == 1 and count(o.calls, 'stop') == 1)
 assert(count(o.calls, 'up') == 0)
end)
test('Already started upgrade prevents WiFi teardown', function()
 local o = ops(); o.upgrading = function()return true end
 assert(core.round(o, {net()}, 'stable')); assert(#o.calls == 0)
end)

-- Production platform code with fake OpenWrt APIs; never executes router commands.
local uci, files = {}, {}
local phys = {}
local unistd = {sleep = function() end, close = function() end, SEEK_SET = 0}
local fcntl = {O_WRONLY = 1, O_CREAT = 2, O_TRUNC = 4, F_SETLK = 6, F_WRLCK = 1,
	F_SETFD = 2, FD_CLOEXEC = 1, open = function() return 9 end, fcntl = function() return 0 end}
local pwait, psignal = {WNOHANG = 1}, {SIGKILL = 9, SIGTERM = 15, SIGINT = 2, SIGHUP = 1}
local iwinfo = {}
package.loaded['simple-uci'] = {cursor = function() return uci end}
package.loaded['gluon.util'] = {readfile = function(p) return files[p] end,
	find_phy = function(r) return r.phy end,
	glob = function(pattern) assert(pattern == '/sys/class/ieee80211/*'); return phys end}
package.loaded.iwinfo = iwinfo
package.loaded.jsonc = {parse = function(s) return s == 'down' and {up = false, pending = false} or ready() end}
package.loaded['posix.unistd'] = unistd
package.loaded['posix.sys.wait'] = pwait
package.loaded['posix.signal'] = psignal
package.loaded['posix.fcntl'] = fcntl
package.loaded.bit = {bor = function(...) local n = 0; for _, v in ipairs({...}) do n = n + v end; return n end}
package.loaded['posix.syslog'] = {syslog = function() end}
local r = require 'ffgt-wifi-fallback.runtime'
r.log = function() end
r.pause = function() end
local actual_command = r.command

test('Native exec receives literal argv, without shell', function()
	unistd.fork = function() return 0 end
	local captured
	unistd.execp = function(cmd, args) captured = {cmd, args}; error('exec intercepted') end
	local ssid = "Freifunk ';&$()\\ Test"
	assert(not pcall(actual_command, {'iw', 'dev', 'ffgtfallback', 'connect', ssid}, 5))
	assert(captured[1] == 'iw' and captured[2][4] == ssid)
end)
test('Bounded command killed and reaped', function()
	unistd.fork = function() return 42 end
	local waits, killed = 0, false
	pwait.wait = function(pid, flags) waits = waits + 1; return flags == 0 and pid or 0 end
	psignal.kill = function(pid, sig) assert(pid == 42 and sig == 9); killed = true end
	assert(actual_command({'iw', 'dev'}, 2) == 124)
	assert(killed and waits == 4)
end)
test('Updater command uses blocking wait without timeout', function()
	pwait.wait = function(pid, flags) assert(flags == 0); return pid, 'exited', 0 end
	assert(actual_command({'autoupdater'}, nil) == 0)
end)
test('Native exec failure reported', function()
	pwait.wait = function(pid) return pid, 'exited', 127 end
	assert(actual_command({'missing'}, 2) == 127)
end)
test('Exclusive lock and close-on-exec set', function()
	local calls = {}
	fcntl.fcntl = function(fd, cmd) calls[#calls + 1] = cmd; return 0 end
	assert(r.lock() == 9); assert(calls[1] == fcntl.F_SETLK and calls[2] == fcntl.F_SETFD)
	fcntl.fcntl = function() return nil end; assert(r.lock() == nil)
end)
test('Scan skips bad radio and deduplicates per PHY/BSSID', function()
	uci.foreach = function(_, _, _, cb)
		for _, radio in ipairs({{['.name'] = 'bad', phy = 'phy9'}, {['.name'] = 'radio0', phy = 'phy0'}, {['.name'] = 'radio1', phy = 'phy1'}}) do cb(radio) end
	end
	iwinfo.type = function(name) return name ~= 'bad' and 'nl80211' or nil end
	iwinfo.nl80211 = {scanlist = function()
		return {net(), net(), net('Freifunk', '00:11:22:33:44:56'), net('Other')}
	end}
	assert(#r.scan() == 4)
	iwinfo.nl80211.scanlist = function() error('scan failed') end
	assert(#r.scan() == 0)
end)
test('Connection passes SSID and BSSID separately without -w', function()
	local commands = {}
	r.command = function(argv)
		commands[#commands + 1] = argv
		if argv[4] == 'link' then return 0, 'Connected to 00:11:22:33:44:55 (on ffgtfallback)' end
		return 0, ''
	end
	local n = net('Freifunk Test')
	assert(r.connect(n))
	assert(commands[3][4] == 'connect' and commands[3][5] == n.ssid and commands[3][6] == n.bssid)
	assert(commands[#commands - 1][4] == 'add_device')
	assert(commands[#commands - 1][5] == '{"name":"ffgtfallback","link-ext":true}')
	assert(commands[#commands][1] == 'ubus' and commands[#commands][4] == 'up')
end)
test('Wrong BSSID never starts IPv6', function()
	local starts, links = 0, 0
	r.command = function(argv)
		if argv[1] == 'ubus' and argv[4] == 'up' then starts = starts + 1 end
		if argv[4] == 'link' then links = links + 1 end
		return 0, 'Connected to 00:00:00:00:00:00'
	end
	assert(not r.connect(net())); assert(starts == 0 and links == 30)
end)
test('IPv6 readiness polls own logical interface', function()
	r.command = function(argv)
		assert(argv[1] == 'ubus' and argv[3] == 'network.interface.ffgt_fallback6')
		return 0, 'ready'
	end
	assert(r.ready())
end)
test('IPv6 deadline prevents endless wait', function()
	local n = 0; r.command = function() n = n + 1; return 0, 'down' end
	assert(not r.ready()); assert(n == 60)
end)
test('WiFi teardown waits for interfaces to disappear', function()
	local n = 0
	r.command = function(argv)
		if argv[1] == 'wifi' then return 0 end
		n = n + 1; return 0, n < 3 and 'Interface mesh0' or 'phy#0'
	end
	assert(r.down()); assert(n == 3)
end)
test('Updater preserves branch argument and no outer timeout', function()
	r.command = function(argv, timeout)
		assert(argv[1] == '/usr/sbin/autoupdater' and argv[2] == '-f' and argv[4] == 'stable')
		assert(timeout == nil); return 1
	end
	assert(r.update('stable') == 1)
end)
test('Gateway presence prevents fallback without ping', function()
	r.command = function(argv, timeout)
		assert(argv[1] == 'batctl' and argv[2] == 'gwl' and argv[3] == '-H' and timeout == 5)
		return 0, '* 00:11:22:33:44:55 (255)'
	end
	assert(r.has_gateways() == true)
	r.command = function() return 0, 'No gateways in range.\n' end
	assert(r.has_gateways() == false)
	r.command = function() return 1, '' end
	assert(r.has_gateways() == nil)
end)
test('Ethernet-only node does not invoke iw without nl80211', function()
	phys = {}
	r.command = function() error('iw must not be called without a PHY') end
	assert(r.wifi_state() == 'absent')
end)
test('Disabled radio differs from an iw failure with hardware present', function()
	phys = {'/sys/class/ieee80211/phy0'}
	r.command = function(argv)
		assert(argv[1] == 'iw' and argv[2] == 'dev')
		return 0, 'phy#0'
	end
	assert(r.wifi_state() == 'inactive')
	r.command = function() return 1, '' end
	assert(r.wifi_state() == nil)
end)
test('Only UP interfaces enable their PHY for scanning', function()
	phys = {'/sys/class/ieee80211/phy0', '/sys/class/ieee80211/phy1'}
	r.command = function(argv)
		return 0, argv[2] == 'phy' and 'Wiphy phy0\nWiphy phy1'
			or 'phy#0\n Interface client0\nphy#1\n Interface client1'
	end
	files['/sys/class/net/client0/flags'] = '0x1003\n'
	files['/sys/class/net/client1/flags'] = '0x1002\n'
	local state, phys = r.wifi_state()
	assert(state == 'active' and phys.phy0 and not phys.phy1)
end)
test('Failed device registration prevents protocol start', function()
	local starts = 0
	r.command = function(argv)
		if argv[4] == 'link' then return 0, 'Connected to 00:11:22:33:44:55' end
		if argv[4] == 'add_device' then return 1 end
		if argv[4] == 'up' then starts = starts + 1 end
		return 0, ''
	end
	assert(not r.connect(net()) and starts == 0)
end)
local v4 = 'br-wan 00000000 0100000A 0003 0 0 10 00000000 0 0 0\n'
local v6 = string.rep('0', 32) .. ' 00 ' .. string.rep('0', 32)
	.. ' 00 fe800000000000000000000000000001 00000400 00000000 00000000 00000003 br-wan\n'
test('WAN accepts IPv4 IPv6 and both default routes', function()
	local routes = core.wan_routes(v4, v6)
	assert(routes[4] and routes[6])
	assert(core.wan_routes(v4, '')[4] and not core.wan_routes(v4, '')[6])
	assert(core.wan_routes('', v6)[6] and not core.wan_routes('', v6)[4])
end)
test('Other interfaces reject routes and non-default routes are ignored', function()
	assert(not next(core.wan_routes(v4:gsub('br%-wan', 'br-client'), v6:gsub('br%-wan', 'lo'))))
	assert(not next(core.wan_routes(v4:gsub('0003', '0203'), v6:gsub('00000003', '00000203'))))
	assert(not next(core.wan_routes(v4:gsub('0003', '0002'), v6:gsub('00000003', '00000002'))))
	assert(not next(core.wan_routes(v4:gsub('00000000 0 0 0', '00FFFFFF 0 0 0'), v6:gsub(' 00 ', ' 40 ', 1))))
end)
test('WAN requires an existing br-wan', function()
	files['/proc/net/route'], files['/proc/net/ipv6_route'] = v4, v6
	assert(not next(r.wan_routes()))
	files['/sys/class/net/br-wan/ifindex'] = '5'
	assert(r.wan_routes()[4] and r.wan_routes()[6])
end)
test('WAN updater marks only its child and has no kill timeout', function()
	r.command = function(argv, timeout)
		assert(argv[1] == 'env' and argv[2] == 'LD_PRELOAD=libpacketmark.so')
		assert(argv[3] == 'LIBPACKETMARK_MARK=1' and argv[4] == '/usr/bin/gluon-wan')
		assert(argv[5] == '/usr/sbin/autoupdater' and argv[6] == '-f' and argv[7] == '-b')
		assert(argv[8] == 'offline6' and timeout == nil)
		return 0
	end
	assert(r.update_wan('offline6') == 0)
end)
local function wan_ops()
	local calls = {}
	return {calls = calls, upgrading = function() return false end,
		cancelled = function() return false end, has_gateways = function() return false end,
		wan_routes = function() return {[4] = true, [6] = true} end,
		branch_exists = function() return true end, log = function() end,
		update_wan = function(branch) calls[#calls + 1] = branch; return 0 end}
end
test('WAN tries both branches even after exit zero', function()
	local o = wan_ops(); assert(core.wan_round(o))
	assert(#o.calls == 2 and o.calls[1] == 'offline4' and o.calls[2] == 'offline6')
end)
test('WAN missing routes and branches skip only that family', function()
	local o = wan_ops(); o.wan_routes = function() return {[6] = true} end
	assert(core.wan_round(o) and #o.calls == 1 and o.calls[1] == 'offline6')
	o = wan_ops(); o.branch_exists = function(b) return b ~= 'offline4' end
	assert(core.wan_round(o) and #o.calls == 1 and o.calls[1] == 'offline6')
end)
test('WAN stops on upgrade handoff cancellation or new gateway', function()
	for _, condition in ipairs({'upgrading', 'cancelled', 'has_gateways'}) do
		local o = wan_ops()
		o[condition] = function() return #o.calls > 0 end
		assert(core.wan_round(o) and #o.calls == 1)
	end
	local o = wan_ops(); o.has_gateways = function() return nil end
	assert(not core.wan_round(o) and #o.calls == 0)
end)

-- Upgrade script: exercise generated UCI configuration and cron scheduling.
test('Upgrade preserves disabled setting and configures IPv6 firewall', function()
	local data = {['autoupdater-wifi-fallback/settings'] = {enabled = false}}
	uci.get = function(_, c, s) return data[c .. '/' .. s] end
	uci.get_bool = function() return false end
	uci.delete = function(_, c, s, o) if not o then data[c .. '/' .. s] = nil end end
	uci.section = function(_, c, _, s, values) data[c .. '/' .. s] = values end
	uci.save = function() end
	local original_open = io.open; local cron
	io.open = function(path, mode)
		assert(path == '/usr/lib/micron.d/autoupdater-wifi-fallback' and mode == 'w')
		return {write = function(_, text) cron = text end, close = function() end}
	end
	files['/usr/lib/micron.d/autoupdater'] = '55 4 * * * /usr/sbin/autoupdater\n'
	local ok, err = pcall(dofile, 'luasrc/lib/gluon/upgrade/510-autoupdater-wifi-fallback')
	io.open = original_open; assert(ok, err)
	assert(data['autoupdater-wifi-fallback/settings'].enabled == false)
	assert(data['network/ffgt_fallback6'].auto == false)
	assert(data['network/ffgt_fallback6'].reqprefix == 'no')
	assert(data['firewall/ffgt_fallback_dhcp6'].dest_port == '546')
	assert(data['firewall/ffgt_fallback'].forward == 'REJECT')
	assert(data['firewall/ffgt_fallback'].device[1] == 'ffgtfallback')
	assert(data['firewall/ffgt_fallback_icmp6'].src == data['firewall/ffgt_fallback'].name)
	assert(cron:match('^5 %* %* %* %*'))
end)
test('Cleanup stops IPv6 before deleting temporary station', function()
 local calls = {}
 r.command = function(argv)
  calls[#calls + 1] = argv
  return 0, 'down'
 end
 local saved = io.open
 io.open = function(path) assert(path == '/sys/class/net/ffgtfallback/ifindex'); return {close = function()end} end
 local ok, result = pcall(r.stop)
 io.open = saved
 assert(ok and result)
 assert(calls[1][1] == 'ifdown' and calls[#calls][4] == 'del')
end)
test('Incomplete network teardown is reported as failure', function()
 r.command = function()return 0, 'ready' end
 local saved = io.open; io.open = function()return nil end
 local ok, result = pcall(r.stop); io.open = saved
 assert(ok and not result)
end)

test('Recovery requires 15 minutes uptime and one hour outage', function()
 assert(not core.recovery_due(899, 'boot 899 0', 'boot'))
 assert(not core.recovery_due(900, 'boot 900 0', 'boot'))
 assert(not core.recovery_due(3659, 'boot 3659 60', 'boot'))
 assert(not core.recovery_due(3660, 'boot 3600 60', 'boot'))
 assert(core.recovery_due(3660, 'boot 3660 60', 'boot'))
end)
test('Missing online stale malformed or foreign-boot status cannot trigger', function()
 for _, state in ipairs({'boot 4000 -', 'boot 3879 1', 'other 4000 1',
  'boot 4001 1', 'boot 4000 4001', 'boot 4000 -1', 'boot 4000 1 extra', ''}) do
  assert(not core.recovery_due(4000, state, 'boot'), state)
 end
 assert(not core.recovery_due(4000, nil, 'boot'))
 assert(not core.recovery_due(4000, 'boot 4000 1', nil))
 assert(core.recovery_due(4000, 'boot 3880 1\n', 'boot\n'))
end)
test('Runtime reads SSID changer state and monotonic boot identity', function()
 files['/proc/uptime'] = '4000.9 1000.0'
 files['/proc/sys/kernel/random/boot_id'] = 'boot\n'
 files['/tmp/ssid-changer-gateway-status'] = 'boot 3990 60\n'
 assert(r.recovery_due())
 files['/tmp/ssid-changer-gateway-status'] = nil
 assert(not r.recovery_due())
end)

-- Entry point dispatch: timing must gate both WLAN and WAN before work.
local real_runtime = package.loaded['ffgt-wifi-fallback.runtime']
local real_core = package.loaded['ffgt-wifi-fallback.core']
local function entry(options)
 local calls = {round = 0, scan = 0, wan = 0}
 local fake_uci = {get = function() if not options.no_default then return 'stable' end end,
  get_bool = function() return not options.disabled end}
 local fake = {uci = fake_uci, log = function()end,
  recovery_due = function()return not options.not_due end,
  lock = function()return not options.locked and 9 or nil end,
  install_signals = function()end, upgrading = function()return options.upgrading end,
  has_gateways = function() if options.unknown then return nil end; return options.mesh or false end,
  wifi_state = function()return options.wifi or 'active', {phy0 = true} end,
  branch_exists = function()return not options.missing_branch end,
  scan = function(phys) assert(phys.phy0); calls.scan = calls.scan + 1; return {net()} end}
 package.loaded['ffgt-wifi-fallback.runtime'] = fake
 package.loaded['ffgt-wifi-fallback.core'] = {
  round = function()calls.round = calls.round + 1; return true end,
  wan_round = function()calls.wan = calls.wan + 1; return true end}
 local saved_exit, saved_arg = os.exit, arg
 os.exit = function(code) error({exit = code}) end
 arg = options.force and {'-f'} or {}
 local ok, err = pcall(dofile, 'luasrc/usr/sbin/autoupdater-wifi-fallback')
 os.exit, arg = saved_exit, saved_arg
 package.loaded['ffgt-wifi-fallback.runtime'] = real_runtime
 package.loaded['ffgt-wifi-fallback.core'] = real_core
 assert(not ok and type(err) == 'table' and err.exit ~= nil, tostring(err))
 calls.exit = err.exit
 return calls
end
test('Timing gate blocks WLAN and WAN even with force', function()
 for _, wifi in ipairs({'active', 'absent'}) do
  for _, force in ipairs({false, true}) do
   local c = entry({not_due = true, wifi = wifi, force = force})
   assert(c.exit == 0 and c.scan == 0 and c.wan == 0 and c.round == 0)
  end
 end
end)
test('Disabled updater does not start fallback', function()
 local c = entry({disabled = true}); assert(c.exit == 0 and c.scan == 0 and c.wan == 0)
end)
test('Absent gateways allow WLAN fallback after timing gate', function()
 assert(entry({}).round == 1)
end)
test('Force cannot override gateway presence or unknown gateway state', function()
 for _, wifi in ipairs({'active', 'absent'}) do
  local c = entry({force = true, mesh = true, wifi = wifi})
  assert(c.round == 0 and c.wan == 0 and c.scan == 0)
  c = entry({force = true, unknown = true, wifi = wifi})
  assert(c.exit == 1 and c.round == 0 and c.wan == 0)
 end
end)
test('Force may override disabled activation', function()
 assert(entry({force = true, disabled = true}).round == 1)
end)
test('Missing WLAN branch fails before scan', function()
 local c = entry({missing_branch = true, force = true}); assert(c.exit == 1 and c.scan == 0)
end)
test('No WLAN uses WAN even without regular branch', function()
 local c = entry({wifi = 'absent', missing_branch = true, no_default = true})
 assert(c.wan == 1 and c.scan == 0 and c.round == 0)
end)
test('Disabled WLAN is neither scanned nor treated as absent hardware', function()
 local c = entry({wifi = 'inactive'}); assert(c.scan == 0 and c.wan == 0 and c.round == 0)
end)
test('Second instance or existing upgrade leaves network untouched', function()
 for _, opt in ipairs({{locked = true}, {upgrading = true}}) do
  local c = entry(opt); assert(c.exit == 0 and c.scan == 0 and c.wan == 0)
 end
end)
print(string.format('%d tests passed (%s)', total, _VERSION))
