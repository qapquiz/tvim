---@class utils.lualine
local M = {}

local project = require("craftzdog.utils.project")

---Buffer path relative to the cwd or the project root, with the filename in its own highlight group.
---@param opts? {relative: "cwd"|"root", modified_hl: string?, directory_hl: string?, filename_hl: string?, modified_sign: string?, readonly_icon: string?, length: number?}
function M.pretty_path(opts)
	opts = vim.tbl_extend("force", {
		relative = "cwd",
		modified_hl = "MatchParen",
		directory_hl = "",
		filename_hl = "Bold",
		modified_sign = "",
		readonly_icon = " 󰌾 ",
		length = 3,
	}, opts or {})

	return function(self)
		local path = vim.fn.expand("%:p") --[[@as string]]

		if path == "" then
			return ""
		end

		-- Normalize path
		path = project.normalize(path)

		-- Make path relative
		local cwd = project.normalize(project.get_cwd())
		local root = opts.relative == "root" and project.get_root() or cwd

		-- Case-insensitive matching on Windows
		local path_lower = path:lower()
		local root_lower = root:lower()
		if vim.fn.has("win32") == 1 then
			if path_lower:find(root_lower, 1, true) == 1 then
				path = path:sub(#root + 2)
			end
		else
			if path:find(root, 1, true) == 1 then
				path = path:sub(#root + 2)
			end
		end

		-- Split path into segments
		local sep = package.config:sub(1, 1)
		local parts = vim.split(path, "[\\/]")

		-- Truncate if too many segments (when length > 0)
		if opts.length > 0 and #parts > opts.length then
			local truncated = { parts[1], "…" }
			for i = #parts - opts.length + 2, #parts do
				table.insert(truncated, parts[i])
			end
			parts = truncated
		end

		-- Separate directory and filename
		local filename = parts[#parts]
		local dir = ""
		if #parts > 1 then
			dir = table.concat(vim.list_slice(parts, 1, #parts - 1), sep) .. sep
		end

		-- Build the formatted string with highlights
		local hl_group = "lualine_c_normal"
		if self and self.options and self.options.section then
			hl_group = "lualine_" .. self.options.section .. "_normal"
		end

		-- Apply directory highlight
		local dir_hl = opts.directory_hl ~= "" and opts.directory_hl or nil
		local dir_part = dir_hl and ("%#" .. dir_hl .. "#" .. dir .. "%#" .. hl_group .. "#") or dir

		-- Check if modified
		local modified = vim.bo.modified
		local readonly = vim.bo.readonly or not vim.bo.modifiable

		-- Apply filename highlight (modified takes precedence)
		local file_hl = modified and opts.modified_hl or opts.filename_hl
		local file_part = file_hl and file_hl ~= "" and ("%#" .. file_hl .. "#" .. filename .. "%#" .. hl_group .. "#")
			or filename

		-- Build result
		local result = dir_part .. file_part

		-- Add modified sign
		if modified and opts.modified_sign ~= "" then
			result = result .. opts.modified_sign
		end

		-- Add readonly icon
		if readonly then
			result = result .. opts.readonly_icon
		end

		return result
	end
end

---Project root name, shown whenever the root differs from the cwd.
---@param opts? {cwd:false, subdirectory: true, parent: true, other: true, icon?:string}
function M.root_dir(opts)
	opts = vim.tbl_extend("force", {
		cwd = false,
		subdirectory = true,
		parent = true,
		other = true,
		icon = "󱉭 ",
		color = function()
			return { fg = Snacks.util.color("Special") }
		end,
	}, opts or {})

	local function get()
		local cwd = project.normalize(project.get_cwd())
		local root = project.get_root()
		local name = vim.fs.basename(root)

		if root == cwd then
			-- root is cwd
			return opts.cwd and name
		elseif root:find(cwd, 1, true) == 1 then
			-- root is subdirectory of cwd
			return opts.subdirectory and name
		elseif cwd:find(root, 1, true) == 1 then
			-- root is parent directory of cwd
			return opts.parent and name
		else
			-- root and cwd are not related
			return opts.other and name
		end
	end

	return {
		function()
			return (opts.icon and opts.icon .. " ") .. get()
		end,
		cond = function()
			return type(get()) == "string"
		end,
		color = opts.color,
	}
end

--- Shows the register a macro is currently being recorded into.
--- Pair with "RecordingEnter"/"RecordingLeave" in lualine's `options.refresh.events`
--- so it appears and disappears without waiting for the refresh timer.
---@param opts? {icon?:string, color?:table|fun():table}
function M.macro_recording(opts)
	opts = vim.tbl_extend("force", {
		icon = "󰑋 ",
		color = function()
			return { fg = Snacks.util.color("DiagnosticError"), gui = "bold" }
		end,
	}, opts or {})

	return {
		function()
			return opts.icon .. vim.fn.reg_recording()
		end,
		cond = function()
			return vim.fn.reg_recording() ~= ""
		end,
		color = opts.color,
	}
end

return M
