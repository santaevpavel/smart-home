function setupServer()
    local server = net.createServer(net.TCP, 30)
    if server then
        server:listen(80, function(conn)
            local _, ip = conn:getpeer()
            print("Client connected " .. ip)
            conn:on("receive", function(client, request)
                print("Receive: " .. request)
                client:send(createPage(), function()
                    client:close()
                    collectgarbage();
                end)
            end)
        end)
    end
    return server
end

function createPage()
    local page = ""
    local mqtt = settingsMqttSendPeriod / 1000
    local wifi = settingsWifiUpdatePeriod / 1000

    local humidity, temperature = getTemperatureAndHumidityFormatted()
    page = page .. "<h1> ESP8266 Web Server</h1>"
    page = page .. "<font size=\"5\"><br/>Temperature <b>" .. temperature .. "</b>°C</font>"
    page = page .. "<font size=\"5\"><br/>Humidity <b>" .. humidity .. "</b>%</font>"
    page = page .. "<font size=\"5\"><br/><br/>WiFi update period <b>" .. wifi .. "</b> seconds</font>"
    page = page .. "<font size=\"5\"><br/>MQTT update period <b>" .. mqtt .. "</b> seconds</font>"
    return page
end

function getTemperatureAndHumidityFormatted()
    local humidity, temperature = readTemperatureAndHumidity()
    if (humidity ~= nil and temperature ~= nil) then
        return humidity, temperature
    else
        return "N/A", "N/A"
    end
end