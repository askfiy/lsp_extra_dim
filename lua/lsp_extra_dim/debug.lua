local M = {
    plugin_name = "lsp_extra_dim",
}

local function reload_plugin()
    for plugin_name, _ in pairs(package.loaded) do
        if plugin_name:match(M.plugin_name) then
            package.loaded[M.plugin_name] = nil
        end
    end

    require(M.plugin_name).setup()
end

function M.begin()
    vim.keymap.set({ "n" }, "<leader>pr", reload_plugin, {
        silent = true,
        desc = "reload plugin",
    })
end

return M
