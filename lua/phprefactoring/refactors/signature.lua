-- Change signature refactoring module
-- Handles function/method signature changes

local parser = require('phprefactoring.parser')
local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}

-- Execute signature change
function M.execute()
    if not parser.is_in_function_signature() then
        return
    end

    local function_info = M.get_current_function_info()
    if not function_info then
        return
    end

    M.show_signature_editor(function_info)
end

-- Get current function information
function M.get_current_function_info()
    local node = parser.get_current_node()
    if not node then
        return nil
    end

    -- Find the function/method declaration
    local function_node = node
    while function_node do
        local type = function_node:type()
        if type == 'function_definition' or type == 'method_declaration' then
            break
        end
        function_node = function_node:parent()
    end

    if not function_node then
        return nil
    end

    local function_text = parser.get_node_text(function_node)
    local name = function_text:match('function%s+([%w_]+)')

    return {
        name = name or 'unknown',
        node = function_node,
        text = function_text,
        parameters = M.parse_parameters(function_text),
        return_type = M.parse_return_type(function_text)
    }
end

-- Parse function parameters
function M.parse_parameters(function_text)
    local params = {}
    local params_text = function_text:match('%(([^)]*)%)')

    if params_text and params_text ~= '' then
        for param in params_text:gmatch('[^,]+') do
            param = param:gsub('^%s+', ''):gsub('%s+$', '') -- trim
            local type_hint = param:match('^([%w\\]+)%s+')
            local name = param:match('%$([%w_]+)')
            local default_value = param:match('=%s*(.+)$')

            if name then
                table.insert(params, {
                    name = name,
                    type = type_hint,
                    default = default_value,
                    original = param
                })
            end
        end
    end

    return params
end

-- Parse return type
function M.parse_return_type(function_text)
    return function_text:match('%)%s*:%s*([%w\\]+)')
end

-- Show signature editor interface
function M.show_signature_editor(function_info)
    -- For now, show the current signature analysis
    local current_signature = M.build_signature_string(function_info)



    -- Show simple signature change options
    ui.show_input({
        title = 'Change Signature',
        prompt = 'New parameters (comma-separated): ',
        default = M.get_default_parameters(function_info),
        width = 60
    }, function(new_params)
        if new_params and new_params ~= '' then
            M.apply_signature_change(function_info, new_params)
        end
    end)
end

-- Build current signature string
function M.build_signature_string(function_info)
    local params = {}
    for _, param in ipairs(function_info.parameters) do
        table.insert(params, param.original)
    end

    local signature = function_info.name .. '(' .. table.concat(params, ', ') .. ')'

    if function_info.return_type then
        signature = signature .. ': ' .. function_info.return_type
    end

    return signature
end

-- Get default parameters for input
function M.get_default_parameters(function_info)
    local params = {}
    for _, param in ipairs(function_info.parameters) do
        table.insert(params, param.original)
    end
    return table.concat(params, ', ')
end

-- Apply signature change
function M.apply_signature_change(function_info, new_params_str)
    local bufnr = vim.api.nvim_get_current_buf()
    local function_node = function_info.node

    -- Get the current function text to find the signature line
    local start_row, start_col, end_row, end_col = function_node:range()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 3, false)

    -- Find the line containing the function signature
    for i, line in ipairs(lines) do
        if line:match('function%s+' .. vim.pesc(function_info.name)) then
            local line_num = start_row + i - 1

            -- Replace the parameter list in the signature
            local new_line = line:gsub('(%([^)]*)%)', '(' .. new_params_str .. ')')

            -- Update the line in the buffer
            vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })

            return
        end
    end

    ui.show_notification('Could not find function signature to update', 'error')
end

return M
