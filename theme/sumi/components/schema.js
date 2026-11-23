.pragma library
// Generado por tools/sumi-sddm gen desde schema/config-schema.json. No editar a mano.
var VERSION = 1;
var KEYS = {
 "background": {
  "key": "background",
  "type": "path",
  "default": "",
  "extensions": [
   "jpg",
   "jpeg",
   "png",
   "webp"
  ]
 },
 "backgroundFill": {
  "key": "backgroundFill",
  "type": "enum",
  "default": "crop",
  "values": [
   "crop",
   "fit",
   "stretch"
  ]
 },
 "blurRadius": {
  "key": "blurRadius",
  "type": "number",
  "default": 0,
  "min": 0,
  "max": 100
 },
 "dimOpacity": {
  "key": "dimOpacity",
  "type": "number",
  "default": 0.2,
  "min": 0,
  "max": 0.85
 },
 "backgroundColor": {
  "key": "backgroundColor",
  "type": "color",
  "default": "#0c0d10"
 },
 "accentColor": {
  "key": "accentColor",
  "type": "color",
  "default": "#a9bdff"
 },
 "textColor": {
  "key": "textColor",
  "type": "color",
  "default": "#f3f3f5"
 },
 "errorColor": {
  "key": "errorColor",
  "type": "color",
  "default": "#ff8f87"
 },
 "notchColor": {
  "key": "notchColor",
  "type": "color",
  "default": "#000000"
 },
 "fieldColor": {
  "key": "fieldColor",
  "type": "color",
  "default": "#1c1c1f"
 },
 "fontFamily": {
  "key": "fontFamily",
  "type": "string",
  "default": "",
  "maxLength": 64,
  "pattern": "^[A-Za-z0-9 _.\\-]*$"
 },
 "uiScale": {
  "key": "uiScale",
  "type": "number",
  "default": 1.0,
  "min": 0.5,
  "max": 2.0
 },
 "fontScale": {
  "key": "fontScale",
  "type": "number",
  "default": 1.0,
  "min": 0.75,
  "max": 1.5
 },
 "notchCompactWidth": {
  "key": "notchCompactWidth",
  "type": "integer",
  "default": 200,
  "min": 120,
  "max": 480
 },
 "notchCompactHeight": {
  "key": "notchCompactHeight",
  "type": "integer",
  "default": 34,
  "min": 24,
  "max": 64
 },
 "notchExpandedWidth": {
  "key": "notchExpandedWidth",
  "type": "integer",
  "default": 440,
  "min": 340,
  "max": 720
 },
 "notchRadius": {
  "key": "notchRadius",
  "type": "integer",
  "default": 22,
  "min": 4,
  "max": 48
 },
 "notchShoulder": {
  "key": "notchShoulder",
  "type": "integer",
  "default": 12,
  "min": 0,
  "max": 24
 },
 "notchStartExpanded": {
  "key": "notchStartExpanded",
  "type": "bool",
  "default": false
 },
 "notchIdleCollapse": {
  "key": "notchIdleCollapse",
  "type": "integer",
  "default": 60,
  "min": 5,
  "max": 600,
  "allowZero": true
 },
 "clockPosition": {
  "key": "clockPosition",
  "type": "enum",
  "default": "center",
  "values": [
   "center",
   "top-left",
   "top-right",
   "bottom-left",
   "bottom-right"
  ]
 },
 "clockFormat": {
  "key": "clockFormat",
  "type": "enum",
  "default": "24h",
  "values": [
   "24h",
   "12h"
  ]
 },
 "clockSeconds": {
  "key": "clockSeconds",
  "type": "bool",
  "default": false
 },
 "clockScale": {
  "key": "clockScale",
  "type": "number",
  "default": 1.0,
  "min": 0.5,
  "max": 2.0
 },
 "clockWeight": {
  "key": "clockWeight",
  "type": "enum",
  "default": "light",
  "values": [
   "thin",
   "light",
   "regular",
   "medium"
  ]
 },
 "clockOffsetX": {
  "key": "clockOffsetX",
  "type": "integer",
  "default": 0,
  "min": -600,
  "max": 600
 },
 "clockOffsetY": {
  "key": "clockOffsetY",
  "type": "integer",
  "default": 0,
  "min": -400,
  "max": 400
 },
 "dateFormat": {
  "key": "dateFormat",
  "type": "string",
  "default": "dddd, d MMMM",
  "maxLength": 48,
  "pattern": "^[A-Za-z0-9 ,.:/'\\-]*$"
 },
 "userStrip": {
  "key": "userStrip",
  "type": "enum",
  "default": "always",
  "values": [
   "always",
   "auto",
   "never"
  ]
 },
 "avatarSize": {
  "key": "avatarSize",
  "type": "integer",
  "default": 64,
  "min": 40,
  "max": 120
 },
 "userNames": {
  "key": "userNames",
  "type": "bool",
  "default": true
 },
 "userInactiveOpacity": {
  "key": "userInactiveOpacity",
  "type": "number",
  "default": 0.6,
  "min": 0.2,
  "max": 1.0
 },
 "userStripMargin": {
  "key": "userStripMargin",
  "type": "integer",
  "default": 64,
  "min": 16,
  "max": 300
 },
 "manualUser": {
  "key": "manualUser",
  "type": "enum",
  "default": "auto",
  "values": [
   "auto",
   "always",
   "never"
  ]
 },
 "showShutdown": {
  "key": "showShutdown",
  "type": "bool",
  "default": true
 },
 "showRestart": {
  "key": "showRestart",
  "type": "bool",
  "default": true
 },
 "showSuspend": {
  "key": "showSuspend",
  "type": "bool",
  "default": false
 },
 "animations": {
  "key": "animations",
  "type": "bool",
  "default": true
 },
 "animationSpeed": {
  "key": "animationSpeed",
  "type": "number",
  "default": 1.0,
  "min": 0.25,
  "max": 3.0
 },
 "multiMonitor": {
  "key": "multiMonitor",
  "type": "enum",
  "default": "all",
  "values": [
   "all",
   "primary"
  ]
 },
 "authTimeout": {
  "key": "authTimeout",
  "type": "integer",
  "default": 30,
  "min": 5,
  "max": 120
 }
};
