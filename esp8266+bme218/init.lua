dofile("utils.lua")
dofile("constants.lua")
dofile("web.lua")

wifiStatusOld = 0
settingsMqttSendPeriod = MQTT_SEND_PERIOD
settingsWifiUpdatePeriod = TIMER_WIFI_UPDATE_PERIOD
settingsSleepDelay = TIMER_SLEEP_DELAY

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

    print("Settings up i2c bme280...")
    i2c.setup(0, PIN_BME_SDA, PIN_BME_SCL, i2c.SLOW)
    tmr.delay(1000 * 1000)
    print("Settings up bme280...")
    bme280.setup()

    wifiTimer = tmr.create()
    mqttTemperatureAndHumidityTimer = tmr.create()
    sleepTimer = tmr.create()

    wifiConnectAttempts = 0
    mqttConnectAttempts = 0
end

function onWifiTimerTick()
    print("Alarm wifiTimer " .. wifi.STA_GOTIP)
    print("Wifi old status = " .. wifiStatusOld .. ", new status = " .. wifi.sta.status() .. ", wifiConnectAttempts " .. wifiConnectAttempts)

    if wifi.sta.status() == wifi.STA_GOTIP then
        if wifiStatusOld ~= wifi.STA_GOTIP then
            onWifiConnected()
        end
    else
        if wifiConnectAttempts >= 3 then
            startSleepTimer()
        else
            print("Reconnect " .. wifiStatusOld .. " " .. wifi.sta.status())
            mqttTemperatureAndHumidityTimer:stop()
            wifi.sta.connect()
            wifiConnectAttempts = wifiConnectAttempts + 1
        end
    end

    -- save wifi status
    wifiStatusOld = wifi.sta.status()
    collectgarbage()
end

function onWifiConnected()
    print("Connected to WiFi")
    print(wifi.sta.getip())

    local mqttClient = mqtt.Client(MQTT_CLIENT_ID, 120, MQTT_CLIENT_USER, MQTT_CLIENT_PASSWORD)

    -- Mqtt event handlers
    mqttClient:on("connect", function(_)
        print("MQTT connected")
    end)
    mqttClient:on("offline", function(_)
        mqttTemperatureAndHumidityTimer:stop()
        print("MQTT offline")
    end)

    print("Connecting to MQTT broker")
    mqttClient:connect(MQTT_BROKER_IP, MQTT_BROKER_PORT, 0, function(_)
        print("Connected to MQTT broker")
        sendWeatherData(mqttClient)
    end, function(_, reason)
        print("Unable to connect to MQTT broker, reason " .. reason)
        startSleepTimer()
    end)
end

function sendWeatherData(mqttClient)
    local humidity, temperature = readTemperatureAndHumidity()
    if humidity ~= nil and temperature ~= nil then
        print("Temperature = " .. temperature .. " humidity = " .. humidity)

        local isTemperatureMqttSent = mqttClient:publish(MQTT_TEMPERATURE_TOPIC, temperature, 0, 0, function(_)
            print("Temperature sent")
        end)
        local isHumidityMqttSent = mqttClient:publish(MQTT_HUMIDITY_TOPIC, humidity, 0, 0, function(_)
            print("Humidity send")
        end)
        print("MQTT send temp result = ", isTemperatureMqttSent, ", MQTT send humidity result = ", isHumidityMqttSent)
    else
        print("Unable to read temp and hum from sensor")
    end
    startSleepTimer()
end

function enableDeepSleep()
    print("Go to deep sleep")
    node.dsleep(SLEEP_TIME)
end

function readTemperatureAndHumidity()
    local humidityRaw, temperatureRaw = bme280.humi()
    local temperature
    local humidity
    if humidityRaw ~= nil and temperatureRaw ~= nil then
        temperature = string.format("%d.%02d", temperatureRaw / 100, temperatureRaw % 100)
        humidity = string.format("%d.%03d", humidityRaw / 1000, humidityRaw % 1000)
    end
    return humidity, temperature
end

function restartWifiTimer()
    wifiTimer:stop()
    wifiTimer:alarm(settingsWifiUpdatePeriod, tmr.ALARM_AUTO, function()
        onWifiTimerTick()
    end)
end


function startWifiTimer()
    wifiTimer:alarm(settingsWifiUpdatePeriod, tmr.ALARM_AUTO, function()
        onWifiTimerTick()
    end)
end

function startSleepTimer()
    sleepTimer:alarm(settingsSleepDelay, tmr.ALARM_AUTO, function()
        enableDeepSleep()
    end)
end

main()