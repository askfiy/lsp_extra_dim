return {
    -- default foreground color ( str | func)
    color = "#999999",
    hooks = {
        diagnostics_filter = {
            -- after the default filter function runs, the following hook function will be executed
            lsp_filter = function(diagnostics)
                -- get all used diagnostics
                return diagnostics
            end,
            mark_filter = function(diagnostics)
                -- get all unused diagnostics
                return diagnostics
            end,
        },
    },

    -- disable diagnostic styling while dimming the colors?
    --------------------------------------
    -- {}    : do not disable any diagnostic styles
    -- "all" : disable all diagnostic styles
    -- { "parameter", "function", "keyword.function"} : only disable diagnostic styles for specific captures
    --------------------------------------
    -- see `https://github.com/nvim-treesitter/nvim-treesitter/blob/master/CONTRIBUTING.md`
    disable_diagnostic_style = "all",
}
