-- Dumps this config's observable state as JSON. Diff two snapshots to prove a
-- change preserves behavior, or to see what an upstream sync changed.
--
-- Usage, from a checkout of this repository:
--   XDG_CONFIG_HOME="$(dirname "$PWD")" nvim --headless -S scripts/snapshot.lua > before.json
-- The checkout's directory name must be `nvim`, or XDG_CONFIG_HOME must contain
-- an `nvim` symlink to it. Run it from inside a git repository, because gitsigns
-- stores the enclosing branch in a global variable.

local uv = vim.uv
local api = vim.api

local HOME = vim.env.HOME
local FIX = vim.fn.tempname() .. "-tvim-snapshot"
local masked = {
	{ vim.fn.stdpath("config"), "<CONFIG>" },
	{ vim.fn.stdpath("data"), "<DATA>" },
	{ vim.fn.stdpath("state"), "<STATE>" },
	{ vim.fn.stdpath("cache"), "<CACHE>" },
	{ FIX, "<FIX>" },
	{ HOME, "~" },
}

local function mask(s)
	for _, pair in ipairs(masked) do
		s = s:gsub(vim.pesc(pair[1]), function()
			return pair[2]
		end)
	end
	return s
end

local function sort_keys(a, b)
	if type(a) == "number" and type(b) == "number" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

local function is_list(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then
			return false
		end
		if k > n then
			n = k
		end
	end
	return n == #t
end

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, sort_keys)
	return keys
end

local function enc(v, stack, level)
	level = level or 0
	local ty = type(v)
	if ty == "string" then
		return vim.json.encode(mask(v))
	end
	if ty == "number" or ty == "boolean" then
		return tostring(v)
	end
	if v == nil then
		return "null"
	end
	if ty ~= "table" then
		return '"<' .. ty .. '>"'
	end
	assert(not stack[v], "cycle")
	stack[v] = true
	local keys, list = sorted_keys(v), is_list(v)
	local parts = {}
	for _, k in ipairs(keys) do
		local prefix = list and "" or (vim.json.encode(tostring(k)) .. ": ")
		parts[#parts + 1] = string.rep("  ", level + 1) .. prefix .. enc(v[k], stack, level + 1)
	end
	stack[v] = nil
	if #keys == 0 then
		return list and "[]" or "{}"
	end
	local open, close = list and "[" or "{", list and "]" or "}"
	return open .. "\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", level) .. close
end

local modes = { "n", "v", "x", "s", "o", "i", "l", "c", "t" }

local function keymaps(list)
	local out = {}
	for _, mode in ipairs(modes) do
		for _, m in ipairs(list(mode)) do
			out[#out + 1] = {
				mode = mode,
				lhs = m.lhs,
				rhs = m.callback and "<lua>" or m.rhs,
				desc = m.desc,
				silent = m.silent or nil,
				noremap = m.noremap or nil,
				nowait = m.nowait or nil,
				expr = m.expr or nil,
				script = m.script or nil,
			}
		end
	end
	table.sort(out, function(a, b)
		for _, k in ipairs({ "mode", "lhs", "rhs", "desc" }) do
			if a[k] ~= b[k] then
				return tostring(a[k]) < tostring(b[k])
			end
		end
		return false
	end)
	return out
end

local function global_keymaps()
	return keymaps(api.nvim_get_keymap)
end

local function buffer_keymaps(bufnr)
	return keymaps(function(mode)
		return api.nvim_buf_get_keymap(bufnr, mode)
	end)
end

local function options()
	local g, w, b = {}, {}, {}
	for name, info in pairs(api.nvim_get_all_options_info()) do
		local value = function(target)
			return function()
				local v = vim.o[name]
				if target then
					v = target[name]
				end
				return v
			end
		end
		if info.scope == "global" then
			pcall(function()
				g[name] = value()()
			end)
			if info.global_local then
				pcall(function()
					b[name] = value(vim.bo)()
				end)
				pcall(function()
					w[name] = value(vim.wo)()
				end)
			end
		elseif info.scope == "win" and name ~= "statusline" then
			-- lualine embeds a refresh counter in the rendered statusline
			pcall(function()
				w[name] = value(vim.wo)()
			end)
		elseif info.scope == "buf" then
			pcall(function()
				b[name] = value(vim.bo)()
			end)
		end
	end
	return g, w, b
end

local function gvars()
	local out = {}
	for _, name in ipairs(vim.fn.getcompletion("", "var")) do
		if not name:match("^[vbwt]:") then
			out[name] = vim.g[name]
		end
	end
	return out
end

local function commands()
	local out = {}
	for name, c in pairs(api.nvim_get_commands({})) do
		local entry = {}
		for k, v in pairs(c) do
			entry[k] = (k == "callback") and "<lua>" or v
		end
		out[name] = entry
	end
	return out
end

local config_augroups = { UserConfig = true, CursorLine = true, TreesitterStart = true }

local function autocmds()
	local out, refresh = {}, 0
	for _, au in ipairs(api.nvim_get_autocmds({})) do
		if au.desc == "Refresh treesitter folds" then
			refresh = refresh + 1
		end
		local deferred_parsers = au.event == "User" and au.pattern == "MasonToolsUpdateCompleted"
		if (au.group_name and config_augroups[au.group_name]) or au.event == "PackChanged" or deferred_parsers then
			out[#out + 1] = {
				group = au.group_name,
				event = au.event,
				pattern = au.pattern,
				command = au.command,
				desc = au.desc,
				once = au.once or nil,
				nested = au.nested or nil,
				callback = au.callback and "<lua>" or nil,
			}
		end
	end
	table.sort(out, function(a, b)
		return enc(a, {}) < enc(b, {})
	end)
	return { config = out, refresh_treesitter_folds = refresh }
end

local function highlights()
	local out = {}
	for _, name in ipairs({
		"TabLineActive",
		"TabLineInactive",
		"TabLineSepActive",
		"TabLineSepInactive",
		"TabLineFill",
	}) do
		out[name] = api.nvim_get_hl(0, { name = name, link = false })
	end
	return out
end

local function lsp()
	local out = { servers = {} }
	for _, cfg in ipairs(vim.lsp.get_configs()) do
		local name = cfg.name
		if name and vim.lsp.is_enabled(name) then
			out.servers[name] = vim.lsp.config[name]
		end
	end
	out["*"] = vim.lsp.config["*"]
	return out
end

local function conform()
	local ok, c = pcall(require, "conform")
	if not ok then
		return "<not loaded>"
	end
	local out = { formatters_by_ft = c.formatters_by_ft, default_format_opts = c.default_format_opts }
	for _, formatters in pairs(c.formatters_by_ft) do
		for _, name in ipairs(type(formatters) == "table" and formatters or { formatters }) do
			local okc, cfg = pcall(c.get_formatter_config, name)
			if okc then
				out[name] = cfg
			end
		end
	end
	return out
end

local function snacks()
	local ok, s = pcall(require, "snacks")
	if not ok then
		return "<not loaded>"
	end
	local out = {}
	for _, k in ipairs({ "indent", "scroll", "picker", "notifier", "statuscolumn", "words", "lazygit" }) do
		out[k] = s.config[k]
	end
	return out
end

local function plugins()
	local out = {}
	for _, path in ipairs(vim.split(vim.o.runtimepath, ",")) do
		local name = path:match("pack/core/opt/([^/]+)$")
		if name then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

local function filetypes()
	local cases = { "x.mjml", "x.mdx", "x.lua", "x.tsx", "x.md" }
	local out = {}
	for _, name in ipairs(cases) do
		local ft = vim.filetype.match({ filename = name })
		out[name] = { filetype = ft, lang = ft and vim.treesitter.language.get_lang(ft) or nil }
	end
	return out
end

local function blink_keymaps()
	local ok, config = pcall(require, "blink.cmp.config")
	if not ok then
		return "<not loaded>"
	end
	local keymap = require("blink.cmp.keymap")
	return {
		insert = keymap.get_mappings(config.keymap, "default"),
		cmdline = keymap.get_mappings(config.cmdline.keymap, "cmdline"),
	}
end

local function plugin_configs()
	local targets = {
		diagnostics = function()
			return vim.diagnostic.config()
		end,
		gitsigns = function()
			return require("gitsigns.config").config
		end,
		incline = function()
			return require("incline.config").config
		end,
		lualine = function()
			return require("lualine").get_config()
		end,
		mini_diff = function()
			return MiniDiff and MiniDiff.config
		end,
		mini_icons = function()
			return MiniIcons and MiniIcons.config
		end,
		mini_pairs = function()
			return MiniPairs and MiniPairs.config
		end,
	}
	local out = {}
	for name, get in pairs(targets) do
		local ok, v = pcall(get)
		out[name] = ok and v or ("<error: " .. tostring(v) .. ">")
	end
	return out
end

local function module_surface(mod, depth)
	local out = {}
	for _, k in ipairs(sorted_keys(mod)) do
		out[k] = type(mod[k]) == "table" and (depth > 0 and module_surface(mod[k], depth - 1) or "<table>")
			or type(mod[k])
	end
	return out
end

local function notified(fn, ...)
	local saved, msgs = vim.notify, {}
	vim.notify = function(msg, level)
		msgs[#msgs + 1] = string.format("[%s] %s", tostring(level), tostring(msg))
	end
	local result = { pcall(fn, ...) }
	vim.notify = saved
	if not result[1] then
		return { error = tostring(result[2]) }
	end
	table.remove(result, 1)
	return msgs, unpack(result)
end

local function open(file)
	vim.cmd("enew!")
	if file ~= "" then
		vim.cmd("edit " .. vim.fn.fnameescape(file))
	end
end

local function listed_buffers()
	local out = {}
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted then
			out[#out + 1] = api.nvim_buf_get_name(buf) .. (vim.bo[buf].modified and " (+)" or "")
		end
	end
	table.sort(out)
	return out
end

local function path_cases(E, L)
	local default = L.pretty_path()
	local ui = L.pretty_path({
		length = 0,
		relative = "cwd",
		modified_hl = "MatchParen",
		directory_hl = "",
		filename_hl = "Bold",
		modified_sign = "",
		readonly_icon = " 󰌾 ",
	})
	local root = L.root_dir()
	local cases = {
		{ "file_in_project_at_root", FIX .. "/proj/src/deep/dir/file.lua", FIX .. "/proj" },
		{ "file_in_project_in_subdir", FIX .. "/proj/src/deep/dir/file.lua", FIX .. "/proj/src/deep" },
		{ "file_outside_project", FIX .. "/outside/orphan.lua", FIX .. "/proj" },
		{ "file_in_project_cwd_elsewhere", FIX .. "/proj/src/deep/dir/file.lua", FIX .. "/outside" },
		{ "file_via_symlink", FIX .. "/link/src/deep/dir/file.lua", FIX .. "/link" },
		{ "no_file", "", FIX .. "/proj/src" },
	}
	local out = {}
	for _, case in ipairs(cases) do
		local res = {}
		local ok, err = pcall(function()
			open(case[2])
			uv.chdir(case[3])
			local self = { options = { section = "c" } }
			local function snap(label)
				res[label] = {
					path_default = default(self),
					path_ui = ui(self),
					root_name = root.cond() and root[1]() or "<hidden by cond>",
					root_shown = root.cond(),
					root_color = root.color(),
				}
			end
			snap("clean")
			vim.bo.modified = true
			snap("modified")
			vim.bo.modified = false
			vim.bo.modifiable = false
			snap("unmodifiable")
			vim.bo.modifiable = true
			vim.bo.readonly = true
			snap("readonly")
			vim.bo.readonly = false
		end)
		if not ok then
			res.error = tostring(err)
		end
		out[case[1]] = res
	end
	return out
end

local function package_json_cases(E)
	local cases = {
		{ "in_project", FIX .. "/proj/src/deep/dir/file.lua", FIX .. "/proj" },
		{ "no_package_json", FIX .. "/outside/orphan.lua", FIX .. "/outside" },
		{ "no_file", "", FIX .. "/outside" },
	}
	local out = {}
	for _, case in ipairs(cases) do
		local res = {}
		local ok, err = pcall(function()
			open(case[2])
			uv.chdir(case[3])
			local before = {}
			for _, w in ipairs(api.nvim_list_wins()) do
				before[w] = true
			end
			res.notify = notified(E.open_package_json)
			for _, w in ipairs(api.nvim_list_wins()) do
				if not before[w] then
					local cfg = api.nvim_win_get_config(w)
					res.float = {
						title = cfg.title,
						title_pos = cfg.title_pos,
						relative = cfg.relative,
						width = cfg.width,
						height = cfg.height,
						col = cfg.col,
						row = cfg.row,
						border = cfg.border,
						style = cfg.style,
						winblend = vim.wo[w].winblend,
						cursorline = vim.wo[w].cursorline,
						bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(w)),
						keymaps = buffer_keymaps(api.nvim_win_get_buf(w)),
					}
					api.nvim_win_close(w, true)
				end
			end
		end)
		if not ok then
			res.error = tostring(err)
		end
		out[case[1]] = res
	end
	return out
end

local function codeblock_cases(E)
	local cases = {
		{ "lua_lines_1_2", FIX .. "/proj/src/deep/dir/file.lua", 1, 2 },
		{ "tsx_line_2", FIX .. "/proj/widget.tsx", 2, 2 },
		{ "no_file", "", 1, 1 },
	}
	local out = {}
	for _, case in ipairs(cases) do
		local res = {}
		local ok, err = pcall(function()
			open(case[2])
			uv.chdir(FIX .. "/proj")
			vim.fn.setreg("+", "")
			api.nvim_win_set_cursor(0, { case[3], 0 })
			local down = case[4] - case[3]
			vim.cmd(down == 0 and "normal! Vy" or ("normal! V" .. down .. "jy"))
			res.notify = notified(E.copy_as_codeblock)
			res.register = vim.fn.getreg("+")
		end)
		if not ok then
			res.error = tostring(err)
		end
		out[case[1]] = res
	end
	return out
end

local function yank_cases(E)
	local out = {}
	local ok, err = pcall(function()
		open(FIX .. "/proj/src/deep/dir/file.lua")
		uv.chdir(FIX .. "/proj")
		api.nvim_win_set_cursor(0, { 2, 0 })
		vim.fn.setreg("+", "")
		out.relative_notify = notified(E.yank_relative_path_with_line)
		out.relative_register = vim.fn.getreg("+")
		vim.fn.setreg("+", "")
		out.absolute_notify = notified(E.yank_absolute_path_with_line)
		out.absolute_register = vim.fn.getreg("+")
	end)
	if not ok then
		out.error = tostring(err)
	end
	return out
end

local function hidden_buffers_case(E)
	local out = {}
	local ok, err = pcall(function()
		vim.cmd("silent! %bwipeout!")
		vim.cmd("edit " .. vim.fn.fnameescape(FIX .. "/proj/package.json"))
		local clean = api.nvim_create_buf(true, false)
		api.nvim_buf_set_name(clean, FIX .. "/proj/src/deep/dir/file.lua")
		local dirty = api.nvim_create_buf(true, true)
		api.nvim_buf_set_name(dirty, FIX .. "/proj/src/orphan.lua")
		api.nvim_buf_set_lines(dirty, 0, -1, false, { "unsaved" })
		out.before = listed_buffers()
		out.notify = notified(E.delete_hidden_buffers)
		out.after = listed_buffers()
	end)
	if not ok then
		out.error = tostring(err)
	end
	return out
end

local function formatter_toggle_case(E)
	local out = {}
	local ok, err = pcall(function()
		vim.b.disable_autoformat = nil
		out.first = notified(E.toggle_formatter)
		out.value_first = vim.b.disable_autoformat
		out.second = notified(E.toggle_formatter)
		out.value_second = vim.b.disable_autoformat
		vim.b.disable_autoformat = nil
	end)
	if not ok then
		out.error = tostring(err)
	end
	return out
end

local function tabline_cases(T)
	local out = {}
	local ok, err = pcall(function()
		vim.cmd("silent! tabonly!")
		vim.cmd("enew!")
		out.single_unnamed = T.render()
		vim.cmd("tabnew " .. vim.fn.fnameescape(FIX .. "/proj/src/deep/dir/file.lua"))
		vim.bo.modified = true
		vim.cmd("tabnew " .. vim.fn.fnameescape(FIX .. "/proj/a-file-name-longer-than-twenty-characters.lua"))
		vim.cmd("tabnew")
		api.nvim_buf_set_name(0, "oil://" .. FIX .. "/proj/some/deep/directory")
		vim.bo.filetype = "oil"
		vim.cmd("tabnew")
		pcall(api.nvim_set_option_value, "buftype", "terminal", { buf = 0 })
		for i = 1, vim.fn.tabpagenr("$") do
			vim.cmd("tabnext " .. i)
			out["active" .. i] = T.render()
		end
		vim.cmd("silent! tabonly!")
		vim.cmd("enew!")
	end)
	if not ok then
		out.error = tostring(err)
	end
	return out
end

local function lazygit_cases()
	local M = require("craftzdog.utils.lazygit")
	return {
		edit = M.edit_command(),
		edit_at_line = M.edit_command({ at_line = true }),
		focus_without_origin = notified(M.focus_origin),
	}
end

local function scenario(E, L, T)
	return {
		paths = path_cases(E, L),
		package_json = package_json_cases(E),
		codeblock = codeblock_cases(E),
		yank = yank_cases(E),
		hidden_buffers = hidden_buffers_case(E),
		formatter_toggle = formatter_toggle_case(E),
		tabline = tabline_cases(T),
		lazygit = lazygit_cases(),
	}
end

local function fixture()
	local files = {
		["proj/.git/HEAD"] = "ref: refs/heads/main\n",
		["proj/lua/placeholder"] = "",
		["proj/package.json"] = '{\n  "name": "fixture"\n}\n',
		["proj/src/deep/dir/file.lua"] = "local one = 1\nlocal two = 2\n",
		["proj/widget.tsx"] = "export const a = 1\nexport const b = 2\n",
		["proj/a-file-name-longer-than-twenty-characters.lua"] = "",
		["outside/orphan.lua"] = "return {}\n",
	}
	for path, body in pairs(files) do
		local full = FIX .. "/" .. path
		vim.fn.mkdir(vim.fs.dirname(full), "p")
		local f = assert(io.open(full, "w"))
		f:write(body)
		f:close()
	end
	assert(uv.fs_symlink(FIX .. "/proj", FIX .. "/link"))
end

local function remove_fixture()
	vim.fn.delete(FIX, "rf")
end

local function snapshot()
	local E, L, T = Craftzdog.editor, Craftzdog.lualine, Craftzdog.tabline
	local global, win, buf = options()
	local out = {
		meta = {
			version = tostring(vim.version()),
			errmsg = vim.v.errmsg,
			plugins = plugins(),
			modules = module_surface(Craftzdog, 1),
		},
		options = { global = global, window = win, buffer = buf },
		gvars = gvars(),
		keymaps = { global = global_keymaps(), buffer = buffer_keymaps(0) },
		commands = commands(),
		autocmds = autocmds(),
		highlights = highlights(),
		filetypes = filetypes(),
		lsp = lsp(),
		conform = conform(),
		snacks = snacks(),
		blink_keymaps = blink_keymaps(),
		plugins_config = plugin_configs(),
	}
	local cwd = uv.cwd()
	local ok, err = pcall(function()
		fixture()
		out.scenario = scenario(E, L, T)
	end)
	remove_fixture()
	uv.chdir(cwd)
	if not ok then
		out.scenario_error = tostring(err)
	end
	return out
end

local function insert_mode_once()
	pcall(function()
		vim.cmd("startinsert")
		vim.cmd("stopinsert")
	end)
end

vim.defer_fn(function()
	insert_mode_once()
	local ok, err = pcall(snapshot)
	if ok then
		io.write(enc(err, {}, 0), "\n")
	else
		io.stderr:write("snapshot: " .. tostring(err) .. "\n")
	end
	vim.cmd(ok and "qa!" or "cquit!")
end, 2000)
