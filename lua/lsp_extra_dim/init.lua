-- author: askfiy
-- date: 2023-03-14

-- *******************************************************************************************
-- This is a plugin to disable unused extra style in LSP
-- The implementation method is very simple:
--   1. Customize the diagnostic.show method
--   2. Override the show method of handlers other than underline
--   3. Filtering out unused resources, underline's show method will still dim them, but other handler's show methods will disable hints such as dummy text
-- *******************************************************************************************

---@diagnostic disable-next-line: unused-local
local debug = require("lsp_extra_dim.debug")
local default_conf = require("lsp_extra_dim.config")

local M = {
    _conf = {},
}

-- **************************************** CommonFunc ****************************************

local function no_used(diagnostic)
    local info = diagnostic.tags
        or vim.tbl_get(diagnostic, "user_data", "lsp", "tags")
        or diagnostic.code
        or diagnostic._tags

    if type(info) == "string" then
        -- diagnostic.code = `unused-xxxx`
        return info:find(".*[uU]nused.*") ~= nil
    end

    if type(info) == "table" then
        -- info = { 1 }
        -- OR
        -- info = { unnecessary = true }
        -- vim.lsp.protocol.DiagnosticTag.Unnecessary = 1
        local unnecessary = vim.lsp.protocol.DiagnosticTag.Unnecessary
        return vim.tbl_contains(info, unnecessary) or info.unnecessary
    end

    return false
end

local function get_captures(bufnr, row, col)
    -- A node may have multiple capture
    -- For example, it may have both function and method capture
    -- {{"function"}, {"method"}}
    -- The last index capture has the highest priority
    local nodes = vim.treesitter.get_captures_at_pos(bufnr, row, col)

    return vim.tbl_map(function(t)
        return t.capture
    end, nodes)
end

-- **************************************** Diagnostic ****************************************

local function filter_is_used_diagnostic(diagnostics)
    local conf = M.get_conf()

    local is_all = conf.disable_diagnostic_style == "all"
    ---@diagnostic disable-next-line: param-type-mismatch
    local is_list = vim.tbl_islist(conf.disable_diagnostic_style)
    local is_empty = is_list and #conf.disable_diagnostic_style == 0

    if is_empty then
        return diagnostics
    elseif is_all or is_list then
        diagnostics = vim.tbl_filter(function(diagnostic)
            if is_all then
                if no_used(diagnostic) then
                    return false
                end
            else
                -- Diagnostics already used, or unused but present in disable_diagnostic_style will not be returned
                local captures = get_captures(
                    diagnostic.bufnr,
                    diagnostic.lnum,
                    diagnostic.col
                )
                ---@diagnostic disable-next-line: param-type-mismatch
                if
                    no_used(diagnostic)
                    and vim.tbl_contains(
                        ---@diagnostic disable-next-line: param-type-mismatch
                        conf.disable_diagnostic_style,
                        captures[#captures]
                    )
                then
                    return false
                end
            end

            return true
        end, diagnostics)
    else
        assert(
            false,
            "`disable_diagnostic_style` unknown type, expect 'all' or {} or {'parameter', 'function', 'keyword.function', '...'}"
            ---@diagnostic disable-next-line: missing-return
        )
    end

    return conf.hooks.lsp_filter(diagnostics)
end

local function create_diagnostic_handler(handler_opts)
    local show = handler_opts.show
    local hide = handler_opts.hide
    return {
        show = function(namespace, bufnr, diagnostics, opts)
            diagnostics = filter_is_used_diagnostic(diagnostics)
            show(namespace, bufnr, diagnostics, opts)
        end,
        hide = hide,
    }
end

function M.setup(opts)
    M._conf = vim.tbl_deep_extend("force", default_conf, opts or {})

    for handler_name, handler_opts in pairs(vim.diagnostic.handlers) do
        -- underline automatically handles unused parameter discoloration
        if handler_name ~= "underline" then
            vim.diagnostic.handlers[handler_name] =
                create_diagnostic_handler(handler_opts)
        end
    end
end

function M.get_conf()
    return M._conf
end

return M
