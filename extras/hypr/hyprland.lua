local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local hypr_home = config_home .. "/hypr"

package.path = hypr_home .. "/lua/?.lua;" .. hypr_home .. "/lua/?/init.lua;" .. package.path

require("config.options")
require("config.animations")
require("config.monitors")
require("config.rules")
require("config.input")
require("config.binds")
require("config.startup")
