-- Copyright (c) 2026. Distributed under the accompanying BSD-2-Clause LICENSE.
local M = {}

function M.eligible(net)
	return type(net.ssid) == 'string' and #net.ssid > 0 and #net.ssid <= 32
		and not net.ssid:find('%z') and net.ssid:lower():find('freifunk', 1, true)
		and type(net.bssid) == 'string'
		and net.bssid:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$')
		and net.mode == 'Master' and type(net.encryption) == 'table'
		and net.encryption.enabled == false
end

function M.ipv6_ready(status)
	if type(status) ~= 'table' or not status.up then return false end
	local address, route = false, false
	for _, entry in ipairs(status['ipv6-address'] or {}) do
		local a = (entry.address or ''):lower()
		-- Global unicast or ULA; link-local alone cannot reach the mirrors.
		if a:match('^[23]') or a:match('^f[cd]') then address = true end
	end
	for _, entry in ipairs(status.route or {}) do
		if entry.target == '::' and tonumber(entry.mask) == 0 then route = true end
	end
	return address and route and #(status['dns-server'] or {}) > 0
end

-- ops is also used by the deterministic regression tests.
function M.round(ops, candidates, branch)
	if #candidates == 0 or ops.upgrading() then return true end
	local ok, err = xpcall(function()
		assert(ops.down(), 'WiFi teardown failed')
		for _, net in ipairs(candidates) do
			if ops.upgrading() then return end
			if ops.cancelled() then break end
			assert(ops.stop(), 'Cannot stop previous fallback interface')
			ops.log('Trying ' .. net.phy .. ' ' .. net.bssid .. ' ' .. string.format('%q', net.ssid))
			if ops.connect(net) and ops.ready() and not ops.cancelled() then
				-- No outer timeout: never kill autoupdater during sysupgrade.
				local rc = ops.update(branch)
				ops.log('Autoupdater returned ' .. tostring(rc) .. '; trying next AP')
				-- Exit 0 can mean "no newer firmware". A completed flash reboots.
			end
		end
	end, debug.traceback)
	-- sysupgrade may hand off to procd and return before the reboot.
	if ops.upgrading() then
		ops.log('Upgrade started; leaving network untouched until reboot')
		return true
	end
	-- Always try both cleanup operations, even if one raises an error.
	local stop_ok, stop_result = pcall(ops.stop)
	local up_ok, up_result = pcall(ops.up)
	if not ok then ops.log(err) end
	if not stop_ok or not stop_result or not up_ok or not up_result then
		ops.log('Cleanup incomplete; check WiFi/network state')
		return false
	end
	return ok
end

return M
