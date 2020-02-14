dofile("utils.lua")
dofile("constants.lua")

wifiStatusOld = 0
settingsMqttSendPeriod = MQTT_SEND_PERIOD
settingsMqttConnectionPeriod = MQTT_CONNECT_PERIOD
settingsWifiUpdatePeriod = TIMER_WIFI_UPDATE_PERIOD

function main()
    print("Starting...")
    tmr.delay(5 * 1000 * 1000)

    setup()

    startWifiTimer()
end

function setup()
    print("Connect to wifi...")
    wifi.setmode(wifi.STATION)

    station_cfg = {}
    station_cfg.ssid = WIFI_SSID
    station_cfg.pwd = WIFI_PASS

    wifi.sta.config(station_cfg)
    wifi.sta.connect()

    gpio.mode(PIN_RELAY, gpio.OUTPUT)

    wifiTimer = tmr.create()
    mqttSendStatusTimer = tmr.create()
    mqttConnectionTimer = tmr.create()

    relayState = "0"
    gpio.write(PIN_RELAY, gpio.LOW)

    setupButton()
end

function onWifiTimerTick()
    print("Alarm wifiTimer " .. wifi.STA_GOTIP)
    print("Wifi old status = " .. wifiStatusOld .. ", new status = " .. wifi.sta.status())

    if wifi.sta.status() == wifi.STA_GOTIP then
        if wifiStatusOld ~= wifi.STA_GOTIP then
            onWifiConnected()
        end
    else
        print("Reconnect " .. wifiStatusOld .. " " .. wifi.sta.status())
        stopMqttConnectionTimer()
        wifi.sta.connect()
    end

    -- save wifi status
    wifiStatusOld = wifi.sta.status()
    collectgarbage()
end

function onWifiConnected()
    print("Connected to WiFi")
    print(wifi.sta.getip())

    local mqttClient = mqtt.Client(MQTT_CLIENT_ID, 120, MQTT_CLIENT_USER, MQTT_CLIENT_PASSWORD)

    mqttClient:on("connect", function(_)
        print("MQTT connected")
    end)
    mqttClient:on("offline", function(_)
        print("MQTT offline")
        stopMqttTimer()
        startMqttConnectionTimer(mqttClient)
    end)
    connectToMqttBroker(mqttClient)
end

function connectToMqttBroker(mqttClient)
    print("Connecting to MQTT broker")
    mqttClient:connect(MQTT_BROKER_IP, MQTT_BROKER_PORT, 0, function(_)
        print("Connected to MQTT broker")
        stopMqttConnectionTimer()
        mqttClient:on("message", function(_, topic, data)
            onMqttMessageReceive(topic, data)
        end)
        mqttClient:subscribe(MQTT_RELAY_TOPIC, 0, function(_)
            print("Subscribed to MQTT broker")
        end)
        startMqttTimer(mqttClient)
    end, function(_, reason)
        print("Unable to connect to MQTT broker, reason " .. reason)
        startMqttConnectionTimer(mqttClient)
    end)
end

function sendRelayState(mqttClient)
    print("Relay state = " .. relayState)
    isSendRelayState = true
    local isRelayStateMqttSent = mqttClient:publish(MQTT_RELAY_TOPIC, relayState, 0, 0, function(_)
        print("Relay state send")
    end)
    print("MQTT send relay state result = ", isRelayStateMqttSent)
end

function onMqttMessageReceive(topic, data)
    if isSendRelayState then
        isSendRelayState = false
        return
    end
    if data ~= nil then
        print("MQTT message receive " .. topic .. " --> " .. data)
        if topic == MQTT_RELAY_TOPIC then
            toggleRelay(data)
        end
    end
end

function toggleRelay(value)
    lastDetection = tmr.now()
    if value == "0" then
        relayState = "0"
        gpio.write(PIN_RELAY, gpio.LOW)
        print("Toggle relay OFF")
    else
        if value == "1" then
            relayState = "1"
            gpio.write(PIN_RELAY, gpio.HIGH)
            print("Toggle relay ON")
        end

    end
end

function startWifiTimer()
    wifiTimer:alarm(settingsWifiUpdatePeriod, tmr.ALARM_AUTO, function()
        onWifiTimerTick()
    end)
end

function startMqttTimer(mqttClient)
    mqttSendStatusTimer:alarm(settingsMqttSendPeriod, 1, function()
        sendRelayState(mqttClient)
    end)
end

function stopMqttTimer()
    mqttSendStatusTimer:stop()
end

function startMqttConnectionTimer(mqttClient)
    mqttConnectionTimer:alarm(settingsMqttConnectionPeriod, 1, function()
        connectToMqttBroker(mqttClient)
    end)
end

function stopMqttConnectionTimer()
    mqttConnectionTimer:stop()
end

lastDetection = 0

function setupButton()
    gpio.mode(2, gpio.INT)
    gpio.trig(2, "up", function(level, when)
        local delay = when - lastDetection
        print("Motion detected! " .. level .. "  " .. delay)
        if delay > BUTTON_CHANGE_STATE_DELAY or delay < 0 then
            if level == 1 then
                if relayState == "0" then
                    toggleRelay("1")
                else
                    toggleRelay("0")
                end
            end
            lastDetection = when
        end
    end)
end

main()