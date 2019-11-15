WIFI_SSID = "XXX"
WIFI_PASS = "XXX"
MQTT_BROKER_IP = "192.168.0.0"
MQTT_BROKER_PORT = 1883
MQTT_CLIENT_ID = "esp1"
MQTT_CLIENT_USER = "XXX"
MQTT_CLIENT_PASSWORD = "XXX"
MQTT_SEND_PERIOD = 10 * 1000
TEMP_MAX = 50
TEMP_MIN = -30
TEMP_ERROR_DELTA = 1
HUMI_MAX = 100
HUMI_MIN = 0
HUMI_ERROR_DELTA = 1
BME_SDA_PIN = 6
BME_SCL_PIN = 5
TIMER_ALART_PERIOD = 5 * 1000

print("Starting...")
tmr.delay(5 * 1000 * 1000)

print("Connect to wifi...")
wifi.setmode(wifi.STATION)

station_cfg = {}
station_cfg.ssid = WIFI_SSID
station_cfg.pwd = WIFI_PASS

wifi.sta.config(station_cfg)
wifi.sta.connect()

local wifi_status_old = 0

print("Settings up i2c, bme210...")
i2c.setup(0, BME_SDA_PIN, BME_SCL_PIN, i2c.SLOW)
tmr.delay(1000 * 1000)
bme280.setup()

wifiTimer = tmr.create()
mqttTimer = tmr.create()

wifiTimer:alarm(TIMER_ALART_PERIOD, tmr.ALARM_AUTO, function()
    print("Alarm wifiTimer "..wifi.STA_GOTIP)
    print("Wifi old status = "..wifi_status_old..", new status = "..wifi.sta.status())

    if wifi.sta.status() == wifi.STA_GOTIP then
        if wifi_status_old ~= wifi.STA_GOTIP then -- Произошло подключение к Wifi, IP получен
            print("Connected to WiFi")
            print(wifi.sta.getip())

            m = mqtt.Client(MQTT_CLIENT_ID, 120, MQTT_CLIENT_USER, MQTT_CLIENT_PASSWORD)

            -- Определяем обработчики событий от клиента MQTT
            m:on("connect", function(client) print ("mqtt connected") end)
            m:on("offline", function(client)
                mqttTimer:stop()
                print ("mqtt offline")
            end)
            m:on("message", function(client, topic, data)
                print(topic .. ":" )
                if data ~= nil then
                    print(data)
                end
            end)

            print("Connecting to MQTT broker")
            m:connect(MQTT_BROKER_IP, MQTT_BROKER_PORT, 0, function(conn)
                print("Connected to MQTT broker")

                mqttTimer:alarm(MQTT_SEND_PERIOD, 1, function()

                    local humi, temp = bme280.humi()
                    if humi ~= nil and temp ~= nil then
                        local formattedTemp = string.format("%d.%03d", temp / 100, temp % 100)
                        local formattedHum = string.format("%d.%03d", humi / 1000, humi % 1000)

                        print("TEMP = "..formattedTemp)
                        print("HUMI = "..formattedHum)

                        tmr.delay(100)
                        local formattedTemp = string.format("%d.%03d", temp / 100, temp % 100)
                        local formattedHum = string.format("%d.%03d", humi / 1000, humi % 1000)

                        print("TEMP = "..formattedTemp)
                        print("HUMI = "..formattedHum)

                        local p1 = m:publish("/ESP/DHT/TEMP", formattedTemp, 0, 0, function(client) print("sent") end)
                        local p2 = m:publish("/ESP/DHT/HUM", formattedHum, 0, 0, function(client) print("sent") end)
                        print ("MQTT send temp result = ", p1, ", MQTT send humidity result = ", p2)
                    else
                        print("Unable to read temp and hum from sensor")
                    end
                end)
            end, function(client, reason)
                print ("Unable to connect to MQTT broket, reason "..reason)
            end)
        else
            -- подключение есть и не разрывалось, ничего не делаем
        end
    else
        print("Reconnect "..wifi_status_old.." "..wifi.sta.status())
        mqttTimer:stop()
        wifi.sta.connect()
    end

    -- Запоминаем состояние подключения к Wifi для следующего такта таймера
    wifi_status_old = wifi.sta.status()
end)
