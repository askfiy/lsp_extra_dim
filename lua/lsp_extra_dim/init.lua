-- author: askfiy
-- date: 2023-03-14

---@diagnostic disable-next-line: unused-local
local debug = require("lsp_extra_dim.debug")
local default_conf = require("lsp_extra_dim.config")

local M = {
    _conf = {},
}

-- debug.begin()

-- **************************************** CommonFunc ****************************************

local function no_used(diagnostic)
    local info = diagnostic.tags or vim.tbl_get(diagnostic, "user_data", "lsp", "tags") or diagnostic.code

    if type(info) == "string" then
        -- diagnostic.code = `unused-xxxx`
        return info:find(".*[uU]nused.*") ~= nil
    end

    if type(info) == "table" then
        -- info = { 1 }
        -- unnecessary = 1
        local unnecessary = vim.lsp.protocol.DiagnosticTag.Unnecessary
        return vim.tbl_contains(info, unnecessary)
    end

    return false
end

local function is_used(diagnostic)
    return not no_used(diagnostic)
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

---@diagnostic disable-next-line: unused-local, unused-function
local function is_capture(captures, capture_name)
    -- Determine whether the last capture (highest priority) has not captured_name
    local length = #captures
    return captures[length] == capture_name
end

-- **************************************** Diagnostic ****************************************

local function filter_is_used_diagnostic(diagnostics)
    local conf = M.get_conf()

    local is_all = conf.disable_diagnostic_style == "all"
    ---@diagnostic disable-next-line: param-type-mismatch
    local is_list = vim.tbl_islist(conf.disable_diagnostic_style)
    local is_empty = is_list and #conf.disable_diagnostic_style == 0

    diagnostics = vim.tbl_filter(function(diagnostic)
        local line_content =
            vim.api.nvim_buf_get_lines(diagnostic.bufnr, diagnostic.lnum, diagnostic.end_lnum + 1, true)

        if #line_content > 0 and line_content[1]:find(".*ignore%-diagnostic.*") then
            return false
        end

        if is_all then
            return is_used(diagnostic)
        end

        if is_empty then
            return true
        end

        if is_list then
            -- Diagnostics already used, or unused but present in disable_diagnostic_style will not be returned
            local captures = get_captures(diagnostic.bufnr, diagnostic.lnum, diagnostic.col)
            ---@diagnostic disable-next-line: param-type-mismatch
            return not (no_used(diagnostic) and vim.tbl_contains(conf.disable_diagnostic_style, captures[#captures]))
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
        hide = hide,
    }
end

function M.setup(opts)
    M._conf = vim.tbl_deep_extend("force", default_conf, opts or {})

    -- 1. Disable all diagnostics that meet the conditions, such as those that contain the unused keyword and captures is not in disable_diagnostic_style
    -- { underline = {show = <function>, hide = <function>}, virtual_text = {...}, signs = {...} }
    for handler_name, handler_opts in pairs(vim.diagnostic.handlers) do
        vim.diagnostic.handlers[handler_name] = create_diagnostic_handler(handler_opts)
    end
end

function M.get_conf()
    return M._conf
end

return M
