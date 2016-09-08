collectgarbage();
print("Ready to start soft ap")

str=wifi.ap.getmac()
ssidTemp=string.format("%s%s%s",string.sub(str,10,11),string.sub(str,13,14),string.sub(str,16,17));
cfg={}
cfg.ssid="ESP8266_"..ssidTemp;
cfg.pwd="12345678"
wifi.ap.config(cfg)

cfg={}
cfg.ip="192.168.1.1";
cfg.netmask="255.255.255.0";
cfg.gateway="192.168.1.1";
wifi.ap.setip(cfg);
wifi.setmode(wifi.STATIONAP)

str=nil;
ssidTemp=nil;
collectgarbage();

print("Soft AP started")
print("Heep:(bytes)"..node.heap());
print("MAC:"..wifi.ap.getmac().."\r\nIP:"..wifi.ap.getip());

SimpleHttpServer = {}
SimpleHttpServer.__index = SimpleHttpServer

function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))      
    else
      print(formatting .. v)
    end
  end
end

function SimpleHttpServer.error(self, sck, code)
    sck:send("HTTP/1.0 " .. code .. " Error\r\nContent-Type: text/plain\r\n\r\n");
    sck:close()
end

function SimpleHttpServer.html(self, sck, data)
    sck:send("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n" .. data);
    sck:close()
end

function SimpleHttpServer.json(self, sck, data)
    sck:send(
        "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type,Content-Length\r\n\r\n" .. cjson.encode(data),
        function ()
            print("sent!")
            sck:close()
        end
    );
    sck:close()
end

function SimpleHttpServer.options(self, sck)
    sck:send("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type,Content-Length\r\nAccess-Control-Allow-Methods: GET,OPTIONS,POST\r\n\r\n", function () sck:close() end)
--    sck:close()
end

function SimpleHttpServer.route(self, sck, path, data)
    if path == '/' then
        local size = file.list()['index.html']
        local bytesSent = 0
        -- Chunks larger than 1024 don't work.
        -- https://github.com/nodemcu/nodemcu-firmware/issues/1075
        local chunkSize = 1024

        function _send()
            collectgarbage()
    
            -- NodeMCU file API lets you open 1 file at a time.
            -- So we need to open, seek, close each time in order
            -- to support multiple simultaneous clients.
            file.open('index.html')
            file.seek("set", bytesSent)
            local chunk = file.read(chunkSize)
            file.close()
    
            sck:send(chunk, function ()
                bytesSent = bytesSent + #chunk
                chunk = nil
                print("Sent: " .. bytesSent .. " of " .. size)
                if bytesSent < size then 
                    _send()
                else
                    sck:send(" ", function () sck:close() end)
                end
            end)            
        end      

         _send()
        return
    end
    if path == '/api/ap-list.json' then
        wifi.sta.getap(1, function (aps_raw)
            print("Received list of APs")
            tprint(aps_raw, 1)
            aps = {}
            for key,value in pairs(aps_raw) do
                local ssid, rssi, authmode, channel = string.match(value, "([^,]+),([^,]+),([^,]+),([^,]*)")
                rssi = tonumber(rssi)
                if rssi > -30 then
                    strength = 5
                elseif rssi > -67 then
                    strength = 4
                elseif rssi > -70 then
                    strength = 3
                elseif rssi > -80 then
                    strength = 2
                else 
                    strength = 1
                end
                aps[#aps + 1] = { ssid = ssid, strength = strength}
            end
            print("sending");
            self:json(sck, aps)
        end)
        return;
    end
    
    if path == '/api/connect.json' then
        tprint(data)
        if not data then
            self:error(sck, 400)
            return
        end
        wifi.sta.disconnect()
        status = pcall(function () wifi.sta.config(data.ssid, data.password) end)
        if not status then
            return self:json(sck, {success = false, message = "invalid password"})
        end
        wifi.sta.connect()
        tmr.alarm(1, 1000, 1, function()
            print("Status: ")
            print(wifi.sta.status())
             if wifi.sta.status() == 4 then
                 tmr.stop(1)
                 return self:json(sck, {success = false, message = "connection failed"})
             elseif wifi.sta.status() == 2 then
                 tmr.stop(1)
                 return self:json(sck, {success = false, message = "invalid password"})
             elseif wifi.sta.status() == 3 then
                 tmr.stop(1)
                 return self:json(sck, {success = false, message = "AP not found"})
             elseif wifi.sta.status() == 5 then
                 tmr.stop(1)
                 self:json(sck, {success = true, ip = wifi.sta.getip()})
             end
        end)
        return;
    end

    if path == '/api/status.json' then
        if wifi.sta.status() == 5 then
            ssid, password, bssid_set, bssid=wifi.sta.getconfig()
            return self:json(sck, {connected = true, ip = wifi.sta.getip(), ssid = ssid})
        end
        return self:json(sck, {connected = false})
    end

    self:error(sck, 404);
end

function SimpleHttpServer.new()
    local self = setmetatable({}, SimpleHttpServer)
    self.srv = net.createServer(net.TCP)
    self.srv:listen(80, function(conn)
        conn:on("receive", function (sck, payload)
            collectgarbage()

            -- as suggest by anyn99 (https://github.com/marcoskirsch/nodemcu-httpserver/issues/36#issuecomment-167442461)
            -- Some browsers send the POST data in multiple chunks.
            -- Collect data packets until the size of HTTP body meets the Content-Length stated in header
            if payload:find("Content%-Length:") or bBodyMissing then
               if fullPayload then fullPayload = fullPayload .. payload else fullPayload = payload end
               if (tonumber(string.match(fullPayload, "%d+", fullPayload:find("Content%-Length:")+16)) > #fullPayload:sub(fullPayload:find("\r\n\r\n", 1, true)+4, #fullPayload)) then
                  bBodyMissing = true
                  return
               else
                  --print("HTTP packet assembled! size: "..#fullPayload)
                  payload = fullPayload
                  fullPayload, bBodyMissing = nil
               end
            end
            collectgarbage()

            print("request:")
            print(payload);
            r = {}
            e = payload:find("\r\n", 1, true)
            line = payload:sub(1, e - 1)
            _, i, r.method, r.path = line:find("^([A-Z]+) (.-) HTTP/[1-9]+.[0-9]+$")
            
            if r.method == 'OPTIONS' then
                self:options(sck);
                return;
            elseif r.method == 'POST' then
                local bodyStart = payload:find("\r\n\r\n", 1, true)
                                                
                err, body = pcall(function () return cjson.decode(payload:sub(bodyStart, #payload)) end)
                print("JSON Body: ")
                tprint(body, 2)
            else
                local body = nil
            end

            print("Request to " .. r.path)
            self:route(sck, r.path, body)
        end)
    end)
    return self
end

server = SimpleHttpServer.new()

