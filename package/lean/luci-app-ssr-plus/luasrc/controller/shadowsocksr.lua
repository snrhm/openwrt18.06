-- Copyright (C) 2017 yushi studio <ywb94@qq.com>
-- Licensed to the public under the GNU General Public License v3.

module("luci.controller.shadowsocksr", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/shadowsocksr") then
		return
	end
	entry({"admin", "services", "shadowsocksr"}, alias("admin", "services", "shadowsocksr", "client"),_("ShadowSocksR Plus+"), 10).dependent = true
	entry({"admin", "services", "shadowsocksr", "client"}, cbi("shadowsocksr/client"),_("SSR Client"), 10).leaf = true
	entry({"admin", "services", "shadowsocksr", "servers"}, cbi("shadowsocksr/servers"), _("Node List"), 20).leaf = true
	entry({"admin", "services", "shadowsocksr", "servers"}, arcombine(cbi("shadowsocksr/servers", {autoapply=true}), cbi("shadowsocksr/client-config")),_("Node List"), 20).leaf = true
  entry({"admin", "services", "shadowsocksr", "subscription"},cbi("shadowsocksr/subscription"), _("Subscription"),25).leaf = true
	entry({"admin", "services", "shadowsocksr", "control"},cbi("shadowsocksr/control"), _("Access Control"), 30).leaf = true
	entry({"admin", "services", "shadowsocksr", "servers-list"}, cbi("shadowsocksr/servers-list"), _("Severs Nodes"), 40).leaf = true
	entry({"admin", "services", "shadowsocksr", "advanced"},cbi("shadowsocksr/advanced"),_("Advanced Settings"), 50).leaf = true
	if nixio.fs.access("/usr/bin/ssr-server") then
	entry({"admin", "services", "shadowsocksr", "server"},arcombine(cbi("shadowsocksr/server"), cbi("shadowsocksr/server-config")),_("SSR Server"), 60).leaf = true
	end
	entry({"admin", "services", "shadowsocksr", "status"},form("shadowsocksr/status"),_("Status"), 70).leaf = true
	entry({"admin", "services", "shadowsocksr", "check"}, call("check_status"))
	entry({"admin", "services", "shadowsocksr", "refresh"}, call("refresh_data"))
	entry({"admin", "services", "shadowsocksr", "subscribe"}, call("subscribe"))
	entry({"admin", "services", "shadowsocksr", "checkport"}, call("check_port"))
	entry({"admin", "services", "shadowsocksr", "checkports"}, call("check_ports"))
	entry({"admin", "services", "shadowsocksr", "allserver"}, call("get_servers"))
	entry({"admin", "services", "shadowsocksr", "change"}, call("change_node"))
	entry({"admin", "services", "shadowsocksr", "log"},form("shadowsocksr/log"),_("Log"), 80).leaf = true
	entry({"admin", "services", "shadowsocksr","run"},call("act_status")).leaf=true
	entry({"admin", "services", "shadowsocksr", "ping"}, call("act_ping")).leaf=true
end
-- 获取所有节点
function get_servers()
    local uci = luci.model.uci.cursor()
    local server_table = {}
    uci:foreach("shadowsocksr", "servers", function(s)
        s["name"] = s[".name"]
        table.insert(server_table,s)
    end)
    luci.http.prepare_content("application/json")
    luci.http.write_json(server_table)
end

-- 切换节点
function change_node()
    local e={}
    local uci = luci.model.uci.cursor()
    local sid = luci.http.formvalue("set")
    local name = ""
    uci:foreach("shadowsocksr", "global", function(s)
        name = s[".name"]
    end)
    e.status = false
    e.sid = sid
    if sid ~= "" then
    uci:set("shadowsocksr", name, "global_server" , sid)
    luci.sys.call("uci commit shadowsocksr && /etc/init.d/shadowsocksr restart")
    e.status = true
    end
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end

-- 检测全局服务器状态
function act_status()
    local e={}
    --全局服务器
    e.global=luci.sys.call("ps -w | grep ssr-retcp | grep -v grep >/dev/null") == 0

     --检测chinadns状态
	if tonumber(luci.sys.exec("ps -w | grep chinadns |grep -v grep| wc -l"))>0 then
		e.chinadns= true
    elseif tonumber(luci.sys.exec("ps -w | grep pdnsd |grep -v grep| wc -l"))>0 then
		e.chinadns= true
    elseif tonumber(luci.sys.exec("ps -w | grep dns2socks |grep -v grep| wc -l"))>0 then
		e.chinadns= true
    end
     --检测SOCKS5状态
	if tonumber(luci.sys.exec("ps -w | grep microsocks |grep -v grep| wc -l"))>0 then
		e.SOCKS5= true
	  end

 --检测服务端状态
	if tonumber(luci.sys.exec("ps -w | grep ssr-server |grep -v grep| wc -l"))>0 then
		e.server= true
    end
if luci.sys.call("pidof ssr-server >/dev/null") == 0 then
                   e.ssr_server= true
    end
	if luci.sys.call("ps -w | grep v2ray-server | grep -v grep >/dev/null") == 0 then
		e.v2_server= true
	  end
    -- 检测游戏模式状态
    e.game = false
    if tonumber(luci.sys.exec("ps -w | grep ssr-reudp |grep -v grep| wc -l"))>0 then
        e.game= true
    else
        if tonumber(luci.sys.exec("ps -w | grep ssr-retcp |grep \"\\-u\"|grep -v grep| wc -l"))>0 then
            e.game= true
        end
    end
    -- 检测国内通道
    e.baidu = false
    sret = luci.sys.call("/usr/bin/ssr-check www.baidu.com 80 3 1")
    if sret == 0 then
        e.baidu =  true
    end

    -- 检测国外通道
    e.google = false
    sret = luci.sys.call("/usr/bin/ssr-check www.google.com 80 3 1")
    if sret == 0 then
        e.google =  true
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end
function subscribe()
	luci.sys.call("/usr/bin/lua /usr/share/shadowsocksr/subscribe.lua  >> /tmp/ssrplus.log 2>&1")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ ret = 1 })
end

function act_ping()
	local e = {}
	local domain = luci.http.formvalue("domain")
	local port = luci.http.formvalue("port")
	e.index = luci.http.formvalue("index")
	local iret = luci.sys.call(" ipset add ss_spec_wan_ac " .. domain .. " 2>/dev/null")
	local socket = nixio.socket("inet", "stream")
	socket:setopt("socket", "rcvtimeo", 3)
	socket:setopt("socket", "sndtimeo", 3)
	e.socket = socket:connect(domain, port)
	socket:close()
	e.ping = luci.sys.exec("ping -c 1 -W 1 %q 2>&1 | grep -o 'time=[0-9]*.[0-9]' | awk -F '=' '{print$2}'" % domain)
	if (iret == 0) then
		luci.sys.call(" ipset del ss_spec_wan_ac " .. domain)
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function check_status()
	local set = "/usr/bin/ssr-check www." .. luci.http.formvalue("set") .. ".com 80 3 1"
	sret = luci.sys.call(set)
	if sret == 0 then
		retstring ="0"
	else
		retstring ="1"
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json({ ret=retstring })
end

function refresh_data()
local set =luci.http.formvalue("set")
local icount =0

if set == "gfw_data" then
	refresh_cmd="wget-ssl --no-check-certificate https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt -O /tmp/gfw.b64"
	sret=luci.sys.call(refresh_cmd .. " 2>/dev/null")
	if sret== 0 then
	luci.sys.call("/usr/bin/ssr-gfw")
	icount = luci.sys.exec("cat /tmp/gfwnew.txt | wc -l")
	if tonumber(icount)>1000 then
	oldcount=luci.sys.exec("cat /etc/dnsmasq.ssr/gfw_list.conf | wc -l")
	if tonumber(icount) ~= tonumber(oldcount) then
		luci.sys.exec("cp -f /tmp/gfwnew.txt /etc/dnsmasq.ssr/gfw_list.conf")
		luci.sys.exec("cp -f /etc/dnsmasq.ssr/gfw_list.conf /tmp/dnsmasq.ssr/gfw_list.conf")
		luci.sys.call("/etc/init.d/dnsmasq restart")
		retstring=tostring(math.ceil(tonumber(icount)/2))
	else
		retstring ="0"
	end
	else
	retstring ="-1"
	end
	luci.sys.exec("rm -f /tmp/gfwnew.txt ")
else
	retstring ="-1"
end
elseif set == "ip_data" then
	if (luci.model.uci.cursor():get_first('shadowsocksr', 'global', 'chnroute', '0') == '1') then
		refresh_cmd="wget-ssl --no-check-certificate -O - " .. luci.model.uci.cursor():get_first('shadowsocksr', 'global', 'chnroute_url', 'https://pexcn.me/daily/chnroute/chnroute.txt') .. ' > /tmp/china_ssr.txt 2>/dev/null'
	else
		refresh_cmd="wget -O- 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest'  2>/dev/null| awk -F\\| '/CN\\|ipv4/ { printf(\"%s/%d\\n\", $4, 32-log($5)/log(2)) }' > /tmp/china_ssr.txt"
	end
	sret=luci.sys.call(refresh_cmd)
	icount = luci.sys.exec("cat /tmp/china_ssr.txt | wc -l")
	if sret== 0 and tonumber(icount)>1000 then
		oldcount=luci.sys.exec("cat /etc/china_ssr.txt | wc -l")
		if tonumber(icount) ~= tonumber(oldcount) then
			luci.sys.exec("cp -f /tmp/china_ssr.txt /etc/china_ssr.txt")
			retstring=tostring(tonumber(icount))
		else
			retstring ="0"
		end
	else
		retstring ="-1"
	end
	luci.sys.exec("rm -f /tmp/china_ssr.txt ")
else
if nixio.fs.access("/usr/bin/wget-ssl") then
	refresh_cmd="wget-ssl --no-check-certificate -O - ".. luci.model.uci.cursor():get_first('shadowsocksr', 'global', 'adblock_url','https://easylist-downloads.adblockplus.org/easylistchina+easylist.txt') .." > /tmp/adnew.conf"
end
sret=luci.sys.call(refresh_cmd .. " 2>/dev/null")
if sret== 0 then
	luci.sys.call("/usr/bin/ssr-ad")
	icount = luci.sys.exec("cat /tmp/ad.conf | wc -l")
	if tonumber(icount)>1000 then
	if nixio.fs.access("/etc/dnsmasq.ssr/ad.conf") then
		oldcount=luci.sys.exec("cat /etc/dnsmasq.ssr/ad.conf | wc -l")
	else
		oldcount=0
	end
	if tonumber(icount) ~= tonumber(oldcount) then
		luci.sys.exec("cp -f /tmp/ad.conf /etc/dnsmasq.ssr/ad.conf")
		retstring=tostring(math.ceil(tonumber(icount)))
		if oldcount==0 then
		 luci.sys.exec("cp -f /etc/dnsmasq.ssr/ad.conf /tmp/dnsmasq.ssr/ad.conf")
		 luci.sys.call("/etc/init.d/dnsmasq restart")
		end
	else
		retstring ="0"
	end
	else
	retstring ="-1"
	end
	luci.sys.exec("rm -f /tmp/ad.conf")
else
	retstring ="-1"
end
end
luci.http.prepare_content("application/json")
luci.http.write_json({ ret=retstring ,retcount=icount})
end

function check_port()
local set=""
local retstring="<br /><br />"
local s
local server_name = ""
local shadowsocksr = "shadowsocksr"
local uci = luci.model.uci.cursor()
local iret=1
uci:foreach(shadowsocksr, "servers", function(s)
	if s.alias then
		server_name=s.alias
	elseif s.server and s.server_port then
		server_name= "%s:%s" %{s.server, s.server_port}
	end
	iret=luci.sys.call(" ipset add ss_spec_wan_ac " .. s.server .. " 2>/dev/null")
	socket = nixio.socket("inet", "stream")
	socket:setopt("socket", "rcvtimeo", 3)
	socket:setopt("socket", "sndtimeo", 3)
	ret=socket:connect(s.server,s.server_port)
	if  tostring(ret) == "true" then
	socket:close()
	retstring =retstring .. "<font color='green'>[" .. server_name .. "] OK.</font><br />"
	else
	retstring =retstring .. "<font color='red'>[" .. server_name .. "] Error.</font><br />"
	end
	if  iret== 0 then
	luci.sys.call(" ipset del ss_spec_wan_ac " .. s.server)
	end
end)
luci.http.prepare_content("application/json")
luci.http.write_json({ ret=retstring })
end

function check_port()
    local sockets = require "socket"
    local set = luci.http.formvalue("host")
    local port = luci.http.formvalue("port")
    local retstring = ""
    local iret = 1
    iret = luci.sys.call(" ipset add ss_spec_wan_ac " .. set .. " 2>/dev/null")
    socket = nixio.socket("inet", "stream")
    socket:setopt("socket", "rcvtimeo", 3)
    socket:setopt("socket", "sndtimeo", 3)
    local t0 = sockets.gettime()
    ret = socket:connect(set, port)
    if tostring(ret) == "true" then
        socket:close()
        retstring = "1"
    else
        retstring = "0"
    end
    if iret == 0 then
        luci.sys.call(" ipset del ss_spec_wan_ac " .. set)
    end
    local t1 = sockets.gettime()
    local tt =t1 -t0
    luci.http.prepare_content("application/json")
    luci.http.write_json({ret = retstring , used = math.floor(tt*1000 + 0.5)})
end
