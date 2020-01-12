dofile("utils.lua")
dofile("constants.lua")
dofile("web.lua")

wifiStatusOld = 0
settingsMqttSendPeriod = MQTT_SEND_PERIOD
settingsWifiUpdatePeriod = TIMER_WIFI_UPDATE_PERIOD

function main()
    print("Starting...")
    tmr.delay(5 * 1000 * 1000)

    setup()

    startWifiTimer()

    setupServer()
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

    gpio.mode(PIN_RELAY, gpio.OUTPUT)

    wifiTimer = tmr.create()
    mqttTemperatureAndHumidityTimer = tmr.create()
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
        mqttTemperatureAndHumidityTimer:stop()
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

        mqttClient:on("message", function(_, topic, data)
            onMqttMessageReceive(topic, data)
        end)
        mqttClient:subscribe(MQTT_RELAY_TOPIC, 0, function(_)
            print("subscribe success!!!")
        end)

        startMqttTimer(mqttClient)
    end, function(_, reason)
        print("Unable to connect to MQTT broker, reason " .. reason)
    end)
end

function sendWeatherData(mqttClient)
    local humidity, temperature = readTemperatureAndHumidity()
    local co2 = adc.read(0)
    if co2 ~= nil then
        print("CO2 = " .. co2)
        local isCO2MqttSent = mqttClient:publish(MQTT_CO2_TOPIC, co2, 0, 0, function(_)
            print("Temperature sent")
        end)
        print("MQTT send CO2 result = ", isCO2MqttSent)
    end
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

function onMqttMessageReceive(topic, data)
    if data ~= nil then
        print("Mqtt message receive " .. topic .. " --> " .. data)
        if topic == MQTT_RELAY_TOPIC then
            toggleRelay(data)
        end
    end
end

function toggleRelay(value)
    if value == "0" then
        gpio.write(PIN_RELAY, gpio.LOW)
    else
        if value == "1" then
            gpio.write(PIN_RELAY, gpio.HIGH)
        else
        end

    end
end

function restartWifiTimer()
    wifiTimer:stop()
    wifiTimer:alarm(settingsWifiUpdatePeriod, tmr.ALARM_AUTO, function()
        onWifiTimerTick()
    end)
end

function restartMqttTimer()
    mqttTemperatureAndHumidityTimer:stop()
    mqttTemperatureAndHumidityTimer:alarm(settingsMqttSendPeriod, 1, function()
        sendWeatherData(mqttClient)
    end)
end

function startWifiTimer()
    wifiTimer:alarm(settingsWifiUpdatePeriod, tmr.ALARM_AUTO, function()
        onWifiTimerTick()
    end)
end

function startMqttTimer(mqttClient)
    mqttTemperatureAndHumidityTimer:alarm(settingsMqttSendPeriod, 1, function()
        sendWeatherData(mqttClient)
    end)
end

main()