-- author: askfiy
-- date: 2023-03-14

-- *******************************************************************************************
-- This is a plugin to disable unused extra style in LSP
-- The implementation method is very simple:
--   1. Customize the diagnostic.show method
--   2. Filter all diagnostics and clear all unused diagnostics
--   3. Create a mark and put it in a specific namespace (clear the namespace when diagnostics is triggered again)
-- *******************************************************************************************

---@diagnostic disable-next-line: unused-local
local debug = require("lsp_extra_dim.debug")
local default_conf = require("lsp_extra_dim.config")

local M = {
    _conf = {},
    _highlight_name = "DiagnosticUnnecessary",
    _mark_namespace = vim.api.nvim_create_namespace("lsp_extra_dim"),
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

-- **************************************** Marks ****************************************

local function clear_marks(bufnr)
    -- Refresh all marks, essentially clean up all the marks in the namespace
    mark_namespace = M.get_mark_namespace()

    local marks = vim.api.nvim_buf_get_extmarks(0, mark_namespace, 0, -1, {})
    for _, mark in ipairs(marks) do
        vim.api.nvim_buf_clear_namespace(bufnr, mark_namespace, mark[2], mark[2] + 1)
    end
end

local function create_mark(diagnostic)
    -- Create a new mark into the namespace
    mark_namespace = M.get_mark_namespace()

    vim.api.nvim_buf_set_extmark(diagnostic.bufnr, mark_namespace, diagnostic.lnum, diagnostic.col, {
        end_line = diagnostic.lnum,
        end_col = diagnostic.end_col,
        hl_group = M.get_highlight_name(),
        priority = 200,
        end_right_gravity = true,
        strict = false,
    })
end

-- **************************************** Diagnostic ****************************************

local function filter_is_used_diagnostic(diagnostics)
    local conf = M.get_conf()

    local is_all = conf.disable_diagnostic_style == "all"
    ---@diagnostic disable-next-line: param-type-mismatch
    local is_list = vim.tbl_islist(conf.disable_diagnostic_style)
    local is_empty = is_list and #conf.disable_diagnostic_style == 0

    diagnostics = vim.tbl_filter(function(diagnostic)
        if is_empty then
            return true
        end

        if is_all then
            if no_used(diagnostic) then
                create_mark(diagnostic)
                return false
            end
            return true
        end

        if is_list then
            -- Diagnostics already used, or unused but present in disable_diagnostic_style will not be returned
            local captures = get_captures(diagnostic.bufnr, diagnostic.lnum, diagnostic.col)
            ---@diagnostic disable-next-line: param-type-mismatch
            if no_used(diagnostic) and vim.tbl_contains(conf.disable_diagnostic_style, captures[#captures]) then
                create_mark(diagnostic)
                return false
            end
            return true
        end

        assert(
            false,
            "`disable_diagnostic_style` unknown type, expect 'all' or {} or {'parameter', 'function', 'keyword.function', '...'}"
            ---@diagnostic disable-next-line: missing-return
        )
    end, diagnostics)

    return conf.hooks.diagnostics_filter.lsp_filter(diagnostics)
end

local function create_diagnostic_handler(handler_opts)
    local show = handler_opts.show
    local hide = handler_opts.hide

    return {
        show = function(namespace, bufnr, diagnostics, opts)
            diagnostics = filter_is_used_diagnostic(diagnostics)
            show(namespace, bufnr, diagnostics, opts)
        end,
        hide = function(namespace, bufnr)
            hide(namespace, bufnr)
            clear_marks(bufnr)
        end,
    }
end

function M.setup(opts)
    M._conf = vim.tbl_deep_extend("force", default_conf, opts or {})

    for handler_name, handler_opts in pairs(vim.diagnostic.handlers) do
        vim.diagnostic.handlers[handler_name] = create_diagnostic_handler(handler_opts)
    end
end

function M.get_conf()
    return M._conf
end

function M.get_mark_namespace()
    return M._mark_namespace
end

function M.get_highlight_name()
    return M._highlight_name
end

return M
