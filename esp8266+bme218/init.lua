WIFI_SSID = "XXX"
WIFI_PASS = "XXX"
MQTT_BROKER_IP = "192.168.0.0"
MQTT_BROKER_PORT = 1883
MQTT_CLIENT_ID = "esp1"
MQTT_CLIENT_USER = "XXX"
MQTT_CLIENT_PASSWORD = "XXX"
MQTT_SEND_PERIOD = 10 * 1000
MQTT_TEMPERATURE_TOPIC = "/ESP/DHT/TEMP"
MQTT_HUMIDITY_TOPIC = "/ESP/DHT/HUM"
TEMP_MAX = 50
TEMP_MIN = -30
TEMP_ERROR_DELTA = 1
HUMI_MAX = 100
HUMI_MIN = 0
HUMI_ERROR_DELTA = 1
BME_SDA_PIN = 6
BME_SCL_PIN = 5
TIMER_WIFI_UPDATE_PERIOD = 5 * 1000

print("Starting...")
tmr.delay(5 * 1000 * 1000)

print("Connect to wifi...")
wifi.setmode(wifi.STATION)

station_cfg = {}
station_cfg.ssid = WIFI_SSID
station_cfg.pwd = WIFI_PASS

wifi.sta.config(station_cfg)
wifi.sta.connect()

local wifiStatusOld = 0

print("Settings up i2c bme280...")
i2c.setup(0, BME_SDA_PIN, BME_SCL_PIN, i2c.SLOW)
tmr.delay(1000 * 1000)
print("Settings up bme280...")
bme280.setup()

wifiTimer = tmr.create()
mqttTemperatureAndHumidityTimer = tmr.create()

wifiTimer:alarm(TIMER_WIFI_UPDATE_PERIOD, tmr.ALARM_AUTO, function()
    onWifiTimerTick()
end)

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
    mqttClient:on("message", function(_, topic, data)
        print(topic .. ":")
        if data ~= nil then
            print(data)
        end
    end)

    print("Connecting to MQTT broker")
    mqttClient:connect(MQTT_BROKER_IP, MQTT_BROKER_PORT, 0, function(_)
        print("Connected to MQTT broker")

        mqttTemperatureAndHumidityTimer:alarm(MQTT_SEND_PERIOD, 1, function()
            sendTemperatureAndHumidity(mqttClient)
        end)
    end, function(_, reason)
        print("Unable to connect to MQTT broker, reason " .. reason)
    end)
end

function sendTemperatureAndHumidity(mqttClient)
    local humidityRaw, temperatureRaw = bme280.humi()
    if humidityRaw ~= nil and temperatureRaw ~= nil then
        local temperature = string.format("%d.%02d", temperatureRaw / 100, temperatureRaw % 100)
        local humidity = string.format("%d.%03d", humidityRaw / 1000, humidityRaw % 1000)

        print("Temperature = " .. temperature .. " humidity = " .. humidity)

        local isTemperatureMqttSent = mqttClient:publish(MQTT_HUMIDITY_TOPIC, temperature, 0, 0, function(_)
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