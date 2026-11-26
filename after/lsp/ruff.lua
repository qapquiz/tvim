-- The ruff server keeps lint diagnostics and code actions. conform formats
-- Python with the ruff command line tool, and ty answers hover.
---@type vim.lsp.Config
return {
	on_attach = function(client)
		client.server_capabilities.hoverProvider = false
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end,
}
