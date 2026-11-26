---@class utils.project
local M = {}

-- Root detection markers
local root_patterns = { ".git", "lua", "package.json", "Makefile", "Cargo.toml", "go.mod", "pyproject.toml" }

--- Get the current working directory
---@return string
function M.get_cwd()
	return vim.uv.cwd() or vim.fn.getcwd()
end

--- Normalize a path (resolve symlinks, ensure consistent format)
---@param path string
---@return string
function M.normalize(path)
	if path:sub(1, 1) == "~" then
		path = vim.fn.expand(path)
	end
	path = vim.uv.fs_realpath(path) or path
	return path:gsub("/$", "")
end

--- Find the project root directory
---@return string
function M.get_root()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		path = M.get_cwd()
	end
	path = vim.fs.dirname(path)

	local root = vim.fs.find(root_patterns, { path = path, upward = true })[1]
	if root then
		return M.normalize(vim.fs.dirname(root))
	end

	return M.normalize(M.get_cwd())
end

return M
