# IotGate

Easy network configuration for IoT devices based on ESP8266 and NodeMCU.

**Under development** - probably not usable yet.

## Contents

* `serve.lua` - simple HTTP server exposing following paths:

    * / [GET] - serves `index.html` file
    * /api/ap-list.json [GET] - returns list of available WiFi access points
    * /api/connect.json [POST] - connect to WiFi network

* `index.html` - HTML frontend - allows selecting WiFi network.
