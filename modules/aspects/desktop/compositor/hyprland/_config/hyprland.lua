local config_file = debug.getinfo(1, "S").source:gsub("^@", "")
local hypr_home = config_file:match("^(.*)/[^/]+$") or "."

package.path = hypr_home .. "/lua/?.lua;" .. hypr_home .. "/lua/?/init.lua;" .. package.path

require("config.options")
require("config.animations")
require("config.monitors")
require("config.rules")
require("config.input")
require("config.binds")
