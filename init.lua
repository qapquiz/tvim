if vim.loader then
	vim.loader.enable()
end

_G.Craftzdog = require("craftzdog.utils")
require("craftzdog.config.options")
require("craftzdog.config.keymaps")
require("craftzdog.config.autocmds")
require("craftzdog.config.commands")
require("craftzdog.config.workarounds")
require("craftzdog.plugins")
