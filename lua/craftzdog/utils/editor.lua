---@class utils.editor
local M = {}

local project = require("craftzdog.utils.project")

--- Check if a file exists
---@param filepath string
---@return boolean
local function file_exists(filepath)
	local stat = vim.uv.fs_stat(filepath)
	return stat ~= nil and stat.type == "file"
end

--- Open package.json in a floating window with 80% width and height
function M.open_package_json()
	local root = project.get_root()
	local package_json = root .. "/package.json"

	if not file_exists(package_json) then
		vim.notify("package.json not found in project root: " .. root, vim.log.levels.WARN)
		return
	end

	-- Calculate 80% dimensions
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)

	-- Center the window
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Create buffer and load file
	local buf = vim.fn.bufadd(package_json)
	vim.fn.bufload(buf)

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
		title = " package.json ",
		title_pos = "center",
	})

	-- Set window options
	vim.wo[win].winblend = 0
	vim.wo[win].cursorline = true

	-- Close on q or <Esc>
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })
end

--- Copy selected lines as a Markdown codeblock with filename and line number
function M.copy_as_codeblock()
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		vim.notify("Buffer has no file name", vim.log.levels.WARN)
		return
	end

	local root = project.get_root()
	local relative = filepath:sub(#root + 2)
	local ft_to_lang = {
		typescriptreact = "tsx",
		javascriptreact = "jsx",
		typescript = "ts",
		javascript = "js",
	}
	local lang = ft_to_lang[vim.bo.filetype] or vim.bo.filetype

	local result = {}
	table.insert(result, "```" .. lang .. ' filename="' .. relative .. '" line=' .. start_line)
	for _, line in ipairs(lines) do
		table.insert(result, line)
	end
	table.insert(result, "```")

	local text = table.concat(result, "\n")
	vim.fn.setreg("+", text)
	vim.notify("Copied " .. #lines .. " lines as codeblock", vim.log.levels.INFO)
end

--- Delete all listed buffers that are not shown in any window
function M.delete_hidden_buffers()
	local visible_bufs = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		visible_bufs[vim.api.nvim_win_get_buf(win)] = true
	end

	local deleted = 0
	local skipped = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted and not visible_bufs[buf] then
			if vim.bo[buf].modified then
				skipped = skipped + 1
			else
				vim.api.nvim_buf_delete(buf, {})
				deleted = deleted + 1
			end
		end
	end

	local msg = "Deleted " .. deleted .. " hidden buffer" .. (deleted == 1 and "" or "s")
	if skipped > 0 then
		msg = msg .. " (" .. skipped .. " skipped, unsaved changes)"
	end
	vim.notify(msg, vim.log.levels.INFO)
end

--- Enable or disable the current buffer's formatter
function M.toggle_formatter()
	local bufnr = vim.api.nvim_get_current_buf()
	local disabled = vim.b[bufnr].disable_autoformat

	if disabled then
		vim.b[bufnr].disable_autoformat = false
		vim.notify("Formatter enabled for this buffer", vim.log.levels.INFO)
	else
		vim.b[bufnr].disable_autoformat = true
		vim.notify("Formatter disabled for this buffer", vim.log.levels.WARN)
	end
end

function M.yank_relative_path_with_line()
	local path = vim.fn.expand("%:.") .. "#L" .. vim.fn.line(".")
	vim.fn.setreg("+", path)
	vim.notify("Yanked: " .. path, vim.log.levels.INFO)
end

function M.yank_absolute_path_with_line()
	local path = vim.fn.expand("%:p") .. "#L" .. vim.fn.line(".")
	vim.fn.setreg("+", path)
	vim.notify("Yanked: " .. path, vim.log.levels.INFO)
end

return M
