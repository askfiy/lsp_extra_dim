-- author: askfiy
-- date: 2023-03-14

-- The implementation of this plugin can be roughly divided into 2 steps:
-- 1. Disable all diagnostics that meet the conditions, such as those that contain the unused keyword and captures is not in disable_diagnostic_style
-- 2. Find all disabled unused diagnostics and add highlighting via extmark

---@diagnostic disable-next-line: unused-local
local debug = require("lsp_extra_dim.debug")
local default_conf = require("lsp_extra_dim.config")

local M = {
    _private = {
        _conf = {},
        _highlight_name = "LspUnusedHighlight",
        _mark_namespace = vim.api.nvim_create_namespace("lsp_extra_dim"),
    },
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

-- **************************************** Extmark ****************************************

local function filter_no_used_diagnostics(diagnostics)
    local conf = M.get_conf()

    diagnostics = vim.tbl_filter(function(diagnostic)
        return no_used(diagnostic)
    end, diagnostics)

    return conf.hooks.diagnostics_filter.mark_filter(diagnostics)
end

local function create_extmark_from_diagnostics(diagnostics)
    local mark_namespace = M.get_mark_namespace()
    local highlight_name = M.get_highlight_name()

    for _, diagnostic in ipairs(diagnostics) do
        vim.api.nvim_buf_set_extmark(diagnostic.bufnr, mark_namespace, diagnostic.lnum, diagnostic.col, {
            end_line = diagnostic.lnum,
            end_col = diagnostic.end_col,
            hl_group = highlight_name,
            priority = 200,
            end_right_gravity = true,
            strict = false,
        })
    end
end

local function refresh(bufnr)
    local mark_namespace = M.get_mark_namespace()

    -- Every time the diagnostics is updated, the previous diagnostics information will be cleared..
    -- So here we also clean up all the marks
    local marks = vim.api.nvim_buf_get_extmarks(0, mark_namespace, 0, -1, {})

    for _, mark in ipairs(marks) do
        local diagnostics = filter_no_used_diagnostics(vim.diagnostic.get(bufnr, {
            lnum = mark[2],
        }))

        vim.api.nvim_buf_clear_namespace(bufnr, mark_namespace, mark[2], mark[2] + 1)

        create_extmark_from_diagnostics(diagnostics)
    end
end

---@diagnostic disable-next-line: unused-local
local function show(_, bufnr, diagnostics, _)
    if vim.in_fast_event() then
        return
    end

    -- Refresh marks
    refresh(bufnr)

    -- Find all unused diagnostics and change their color
    diagnostics = filter_no_used_diagnostics(diagnostics)

    create_extmark_from_diagnostics(diagnostics)
end

local function hide(_, bufnr)
    local is_queued = true

    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
        callback = function()
            is_queued = false
        end,
        once = true,
    })

    -- Make sure the autocommand is only created once
    vim.api.nvim_create_autocmd({ "DiagnosticChanged" }, {
        pattern = { "*" },
        callback = function(args)
            if is_queued and vim.api.nvim_buf_is_valid(bufnr) then
                local diagnostics = args.data.diagnostics
                show(_, bufnr, diagnostics, _)
            end
        end,
    })
end

local function create_extmark_handler()
    return {
        show = show,
        hide = hide,
    }
end

function M.setup(opts)
    M._private._conf = vim.tbl_deep_extend("force", default_conf, opts or {})

    if type(M._private._conf.color) == "function" then
        M._private._conf.color = M._private._conf.color()
    end

    vim.api.nvim_set_hl(0, M._private._highlight_name, { fg = M._private._conf.color })

    -- 1. Disable all diagnostics that meet the conditions, such as those that contain the unused keyword and captures is not in disable_diagnostic_style
    -- { underline = {show = <function>, hide = <function>}, virtual_text = {...}, signs = {...} }
    for handler_name, handler_opts in pairs(vim.diagnostic.handlers) do
        vim.diagnostic.handlers[handler_name] = create_diagnostic_handler(handler_opts)
    end

    -- 2. Find all disabled unused diagnostics and add highlighting via extmark
    -- When creating a custom handler, it will be called once automatically after the new buffer is registered
    vim.diagnostic.handlers["lsp_extra_dim/unused"] = create_extmark_handler()
end

function M.get_conf()
    return M._private._conf
end

function M.get_mark_namespace()
    return M._private._mark_namespace
end

function M.get_highlight_name()
    return M._private._highlight_name
end

return M
