--[[
Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2008 Jo-Philipp Wich <xm@leipzig.freifunk.net>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0
]]--

package 'ffgt-geolocate'


local util = require 'gluon.util'
local fs = require 'nixio.fs'
local site = require 'gluon.site'
local uci = require("simple-uci").cursor()


local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function filehandler(meta, chunk, eof)
	if not fs.access(tmpfile) and not file and chunk and #chunk > 0 then
		file = io.open(tmpfile, "w")
	end
	if file and chunk then
		file:write(chunk)
	end
	if file and eof then
		file:close()
	end
end

local function action_geoloc(http, renderer)
	local nixio = require 'nixio'

	-- Determine state
	local step = tonumber(http:getenv("REQUEST_METHOD") == "POST" and http:formvalue("step")) or 1

	-- Step 1: Select/enter coordinates; if some are there alredy, try reverse geolocation with them
	if step == 1 then
        local lat = uci:get_first("gluon-node-info", 'location', "latitude")
        local lon = uci:get_first("gluon-node-info", 'location', "longitude")

        if not lat then lat = 0 else lat=tonumber(lat) end
        if not lon then lon = 0 else lon=tonumber(lon) end
        if not (lat == 0 and lon == 0) then
            os.execute("/lib/gluon/ffgt-geolocate/rgeo.sh")
        end
		renderer.render_layout('admin/geolocate', nil, 'gluon-web-admin')
	-- Step 2: Try geolocate with the data entered, unless "autolocate" was selected, in which
	--         case we ignore the coordinates entered.
	elseif step == 2 then
		local autolocate = (http:formvalue("autolocate") == "1")
		if (autolocate) then
            os.execute("/lib/gluon/ffgt-geolocate/senddata.sh force")
            renderer.render_layout('admin/geolocate', nil, 'gluon-web-admin')
        else
            local newlat = trim(http:formvalue("lat"))
    	    local newlon = trim(http:formvalue("lon"))
            local cmdstr = string.format("/lib/gluon/ffgt-geolocate/rgeo.sh %s %s", newlat, newlon)
	        os.execute(cmdstr)
		end

	    local location = uci:get_first("gluon-node-info", "location")
        local lat = uci:get_first("gluon-node-info", 'location', "latitude")
        local lon = uci:get_first("gluon-node-info", 'location', "longitude")
        local unlocode = uci:get_first("gluon-node-info", "location", "locode")

        if not lat then lat = 0 else lat=tonumber(lat) end
        if not lon then lon = 0 else lon=tonumber(lon) end
        if (lat == 51.892825) and (lon == 8.383708) then
            lat=51
            lon=9
        end

        if ((lat == 0 and lon == 0) or (lat == 51 and lon == 9)) then
		  renderer.render_layout('admin/geolocate', { rgeo_error = 1, }, 'gluon-web-admin')
		else
          uci:set('gluon', 'core', 'domain', unlocode)
          uci:commit('gluon')
		  os.execute('gluon-reconfigure')
		  renderer.render_layout('admin/geolocate_done', nil, 'gluon-web-admin')
		end
	elseif step == 3 then
--		if http:formvalue("keepcfg") == "1" then
--			fork_exec("/sbin/sysupgrade", tmpfile)
--		else
--			fork_exec("/sbin/sysupgrade", "-n", tmpfile)
--		end
		renderer.render_layout('admin/geolocate_eeeee', nil, 'gluon-web-admin', {
			hidenav = true,
		})
	end
end


local geoloc = entry({"admin", "geolocate"}, call(action_geoloc), _("Geolocation"), 8)
