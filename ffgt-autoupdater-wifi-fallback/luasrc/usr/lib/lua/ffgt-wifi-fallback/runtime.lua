local uci = require('simple-uci').cursor()
local util = require 'gluon.util'
local iwinfo = require 'iwinfo'
local json = require 'jsonc'
local unistd = require 'posix.unistd'
local wait = require 'posix.sys.wait'
local signal = require 'posix.signal'
local fcntl = require 'posix.fcntl'
local bit = require 'bit'
local syslog = require 'posix.syslog'
local core = require 'ffgt-wifi-fallback.core'
local M = { uci = uci }
local iface, network = 'ffgtfallback', 'ffgt_fallback6'
local output = '/tmp/ffgt-wifi-fallback.output'
local interrupted, restoring = false, false

function M.log(message)
	syslog.syslog(syslog.LOG_NOTICE, 'ffgt-wifi-fallback: ' .. message)
	io.stderr:write(message .. '\n')
end

function M.upgrading()
	return util.readfile('/tmp/ffgt-wifi-fallback.upgrading') ~= nil
end

function M.cancelled() return interrupted end
function M.install_signals()
	for _, sig in ipairs({signal.SIGTERM, signal.SIGINT, signal.SIGHUP}) do
		signal.signal(sig, function() interrupted = true end)
	end
end

-- Direct argv execution: received SSIDs are never parsed by a shell.
-- Only capture small status responses; updater output is not buffered in RAM.
function M.command(argv, seconds, capture)
	local fd
	if capture then
		fd = assert(fcntl.open(output, bit.bor(fcntl.O_WRONLY, fcntl.O_CREAT, fcntl.O_TRUNC), 384))
	end
	local pid = unistd.fork()
	if not pid then
		if fd then unistd.close(fd); os.remove(output) end
		return 127, ''
	end
	if pid == 0 then
		if fd then unistd.dup2(fd, 1); unistd.close(fd) end
		local args = {}
		for i = 2, #argv do args[#args + 1] = tostring(argv[i]) end
		unistd.execp(argv[1], args)
		unistd._exit(127)
	end
	if fd then unistd.close(fd) end
	local elapsed, rc = 0, 127
	while true do
		local child, reason, status = wait.wait(pid, seconds and wait.WNOHANG or 0)
		if child == pid then
			rc = reason == 'exited' and status or 128 + (status or 0)
			break
		elseif child == nil then
			-- Interrupted waits are retried; an already reaped child is an error.
			if status ~= 4 then break end
		elseif seconds and (elapsed >= seconds or (interrupted and not restoring)) then
			signal.kill(pid, signal.SIGKILL)
			wait.wait(pid, 0)
			rc = 124
			break
		else
			unistd.sleep(1)
			elapsed = elapsed + 1
		end
	end
	local text = capture and (util.readfile(output) or '') or ''
	if capture then os.remove(output) end
	return rc, text
end

function M.pause() unistd.sleep(1) end
function M.uptime()
	return tonumber((util.readfile('/proc/uptime') or ''):match('^[%d.]+')) or 0
end

function M.lock()
	local fd = fcntl.open('/var/lock/ffgt-wifi-fallback.lock', bit.bor(fcntl.O_WRONLY, fcntl.O_CREAT), 384)
	if not fd then return nil end
	local ok = fcntl.fcntl(fd, fcntl.F_SETLK, {
		l_start = 0, l_len = 0, l_type = fcntl.F_WRLCK, l_whence = unistd.SEEK_SET,
	})
	if not ok then unistd.close(fd); return nil end
	fcntl.fcntl(fd, fcntl.F_SETFD, fcntl.FD_CLOEXEC)
	return fd
end

function M.mesh_reachable()
	local text = util.readfile('/sys/kernel/debug/batman_adv/bat0/gateways') or ''
	for line in text:gmatch('[^\n]+') do
		local mac = line:match('(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)')
		if mac and M.command({'batctl', 'ping', '-t', '2', '-c', '1', mac}, 5, true) == 0 then
			return true
		end
	end
	return false
end

function M.scan()
	local result, seen = {}, {}
	uci:foreach('wireless', 'wifi-device', function(radio)
		if M.cancelled() then return end
		local phy = util.find_phy(radio)
		if not phy then return end
		local kind = iwinfo.type(radio['.name'])
		local backend = kind and iwinfo[kind]
		if not backend then return end
		local ok, list = pcall(backend.scanlist, radio['.name'])
		if not ok or type(list) ~= 'table' then return end
		for _, net in ipairs(list) do
			if core.eligible(net) then
				local key = phy .. '/' .. net.bssid:lower()
				if not seen[key] then
					seen[key] = true
					result[#result + 1] = {phy = phy, ssid = net.ssid,
						bssid = net.bssid:lower(), signal = tonumber(net.signal) or -999}
				end
			end
		end
	end)
	table.sort(result, function(a, b)
		if a.signal ~= b.signal then return a.signal > b.signal end
		return a.phy .. a.bssid < b.phy .. b.bssid
	end)
	return result
end

local function status()
	local rc, text = M.command({'ubus', 'call', 'network.interface.' .. network, 'status'}, 5, true)
	if rc ~= 0 then return nil end
	local ok, value = pcall(json.parse, text)
	return ok and value or nil
end

function M.down()
	if M.command({'wifi', 'down'}, 30) ~= 0 then return false end
	for _ = 1, 30 do
		local rc, text = M.command({'iw', 'dev'}, 5, true)
		if rc == 0 and not text:match('Interface%s') then return true end
		if interrupted then return false end
		M.pause()
	end
	return false
end

function M.stop()
	-- Finish cleanup even after SIGTERM; never apply this to autoupdater.
	local previous = restoring
	restoring = true
	local stopped = M.command({'ifdown', network}, 15) == 0
	local down = false
	for _ = 1, 15 do
		local s = status()
		if s and not s.up and not s.pending then down = true; break end
		M.pause()
	end
	local f = io.open('/sys/class/net/' .. iface .. '/ifindex')
	if f then
		f:close()
		M.command({'iw', 'dev', iface, 'disconnect'}, 5)
		stopped = M.command({'iw', 'dev', iface, 'del'}, 5) == 0 and stopped
	end
	restoring = previous
	return stopped and down
end

function M.up()
	restoring = true
	local ok = M.command({'wifi', 'up'}, 30) == 0
	restoring = false
	return ok
end

function M.connect(net)
	if M.command({'iw', 'phy', net.phy, 'interface', 'add', iface, 'type', 'managed'}, 5) ~= 0 then return false end
	if M.command({'ip', 'link', 'set', 'dev', iface, 'up'}, 5) ~= 0 then return false end
	-- Do not use -w: iw 4.14's event wait has no built-in timeout.
	if M.command({'iw', 'dev', iface, 'connect', net.ssid, net.bssid}, 5) ~= 0 then return false end
	for _ = 1, 30 do
		local rc, text = M.command({'iw', 'dev', iface, 'link'}, 5, true)
		local bssid = text:match('Connected to (%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)')
		if rc == 0 and bssid and bssid:lower() == net.bssid then
			return M.command({'ifup', network}, 15) == 0
		end
		if interrupted then return false end
		M.pause()
	end
	return false
end

function M.ready()
	for _ = 1, 60 do
		if core.ipv6_ready(status()) then return true end
		if interrupted then return false end
		M.pause()
	end
	M.log('No IPv6 address/default route/DNS on fallback interface')
	return false
end

function M.update(branch)
	return M.command({'/usr/sbin/autoupdater', '-f', '-b', branch}, nil)
end

return M
