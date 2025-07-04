-- Introduce/Extract refactoring module
-- Handles variable, constant, field, and parameter introduction

local parser = require('phprefactoring.parser')
local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}

-- Extract/Introduce variable
function M.variable()
    local selection, start_pos, end_pos = parser.get_visual_selection()
    local expression_text = ''

    if selection and #selection > 0 then
        expression_text = table.concat(selection, '\n')
        -- start_pos and end_pos are already set from get_visual_selection()
    else
        -- Try to get expression under cursor
        local node = parser.get_current_node()
        if node then
            -- Check if current node is extractable
            if parser.is_extractable_expression() then
                expression_text = parser.get_node_text(node)
                local start_row, start_col, end_row, end_col = node:range()
                start_pos = { start_row, start_col }
                end_pos = { end_row, end_col }
            else
                -- Try to find a parent node that is extractable
                local current = node:parent()
                while current do
                    local node_type = current:type()
                    -- Check for common extractable expression types
                    if vim.tbl_contains({
                            'function_call_expression',
                            'binary_expression',
                            'unary_expression',
                            'conditional_expression',
                            'member_access_expression',
                            'scoped_call_expression'
                        }, node_type) then
                        expression_text = parser.get_node_text(current)
                        local start_row, start_col, end_row, end_col = current:range()
                        start_pos = { start_row, start_col }
                        end_pos = { end_row, end_col }
                        break
                    end
                    current = current:parent()
                end

                -- If still no extractable expression found, use the original node
                if expression_text == '' then
                    expression_text = parser.get_node_text(node)
                    local start_row, start_col, end_row, end_col = node:range()
                    start_pos = { start_row, start_col }
                    end_pos = { end_row, end_col }
                end
            end
        end
    end

    if expression_text == '' then
        ui.show_notification('No extractable expression found. Try selecting the expression first.', 'warn')
        return
    end

    -- Generate suggested variable name
    local suggested_name = M.generate_variable_name(expression_text)

    ui.show_input({
        title = 'Introduce Variable',
        prompt = 'Variable name: $',
        default = suggested_name,
        width = 40
    }, function(var_name)
        if var_name and var_name ~= '' then
            M.perform_extract_variable(expression_text, '$' .. var_name, start_pos, end_pos)
        end
    end)
end

-- Extract/Introduce constant
function M.constant()
    local selection, start_pos, end_pos = parser.get_visual_selection()
    local value_text = ''

    if selection then
        value_text = table.concat(selection, '\n')
        -- start_pos and end_pos are already set from get_visual_selection()
    else
        -- Try to get value under cursor
        local node = parser.get_current_node()
        if node and parser.is_extractable_value() then
            value_text = parser.get_node_text(node)
            local start_row, start_col, end_row, end_col = node:range()
            start_pos = { start_row, start_col }
            end_pos = { end_row, end_col }
        end
    end

    if value_text == '' then
        ui.show_notification('No extractable value found', 'warn')
        return
    end

    -- Generate suggested constant name
    local suggested_name = M.generate_constant_name(value_text)

    ui.show_input({
        title = 'Introduce Constant',
        prompt = 'Constant name: ',
        default = suggested_name,
        width = 40
    }, function(const_name)
        if const_name and const_name ~= '' then
            M.perform_extract_constant(value_text, const_name, start_pos, end_pos)
        end
    end)
end

-- Extract/Introduce field (class property)
function M.field()
    if not parser.is_in_class() then
        ui.show_notification('Must be inside a class to introduce field', 'warn')
        return
    end

    local selection, start_pos, end_pos = parser.get_visual_selection()
    local value_text = ''

    if selection then
        value_text = table.concat(selection, '\n')
        -- start_pos and end_pos are already set from get_visual_selection()
    else
        local node = parser.get_current_node()
        if node and parser.is_extractable_value() then
            value_text = parser.get_node_text(node)
            local start_row, start_col, end_row, end_col = node:range()
            start_pos = { start_row, start_col }
            end_pos = { end_row, end_col }
        end
    end

    if value_text == '' then
        ui.show_notification('No extractable value found', 'warn')
        return
    end

    local suggested_name = M.generate_field_name(value_text)

    ui.show_input({
        title = 'Introduce Field',
        prompt = 'Field name: $',
        default = suggested_name,
        width = 40
    }, function(field_name)
        if field_name and field_name ~= '' then
            M.perform_extract_field(value_text, '$' .. field_name, start_pos, end_pos)
        end
    end)
end

-- Extract/Introduce parameter
function M.parameter()
    if not parser.is_in_function() then
        ui.show_notification('Must be inside a function to introduce parameter', 'warn')
        return
    end

    local selection, start_pos, end_pos = parser.get_visual_selection()
    local value_text = ''

    if selection then
        value_text = table.concat(selection, '\n')
        -- start_pos and end_pos are already set from get_visual_selection()
    else
        local node = parser.get_current_node()
        if node and parser.is_extractable_value() then
            value_text = parser.get_node_text(node)
            local start_row, start_col, end_row, end_col = node:range()
            start_pos = { start_row, start_col }
            end_pos = { end_row, end_col }
        end
    end

    if value_text == '' then
        ui.show_notification('No extractable value found', 'warn')
        return
    end

    local suggested_name = M.generate_parameter_name(value_text)

    ui.show_input({
        title = 'Introduce Parameter',
        prompt = 'Parameter name: $',
        default = suggested_name,
        width = 40
    }, function(param_name)
        if param_name and param_name ~= '' then
            M.perform_extract_parameter(value_text, '$' .. param_name, start_pos, end_pos)
        end
    end)
end

-- Perform variable extraction
function M.perform_extract_variable(expression, var_name, start_pos, end_pos)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Trim whitespace from expression to avoid issues
    expression = vim.trim(expression)

    -- Find the best place to insert the variable declaration
    local insert_line = M.find_variable_insert_position()

    -- Create the variable declaration
    local declaration = string.format('%s = %s;', var_name, expression)
    local indent = M.get_current_indentation(insert_line)

    -- Try multi-occurrence replacement first
    local success = pcall(function()
        M.apply_multi_occurrence_replacement(expression, var_name, insert_line, declaration, indent)
    end)

    if not success then
        -- Fallback to single replacement if multi-occurrence fails
        M.apply_simple_extract_variable(expression, var_name, start_pos, end_pos, insert_line, declaration, indent)
    end
end

-- Perform field extraction
function M.perform_extract_field(value, field_name, start_pos, end_pos)
    local conf = config.get()

    -- Find class to add field to
    local class_start = M.find_class_start()
    if not class_start then
        ui.show_notification('Could not find class to add field to', 'error')
        return
    end

    -- Create field declaration (private by default)
    local declaration = string.format('    private %s = %s;', field_name, value)

    -- Apply the refactoring
    M.apply_extract_field(value, field_name, start_pos, end_pos, class_start, declaration)
end

-- Apply field extraction changes
function M.apply_extract_field(value, field_name, start_pos, end_pos, class_start, declaration)
    local bufnr = vim.api.nvim_get_current_buf()
    local inserted_new_field = false

    -- Check if this field is already declared in the current class
    local existing_declaration = M.find_existing_field_declaration(field_name)
    if existing_declaration then
        -- Check if the existing field has a value
        local lines = vim.api.nvim_buf_get_lines(bufnr, existing_declaration, existing_declaration + 1, false)
        local existing_line = lines[1] or ''

        if existing_line:match('=%s*.*;') then
            -- Field already has a value, just do replacements
        else
            -- Field exists but has no value, update it
            vim.api.nvim_buf_set_lines(bufnr, existing_declaration, existing_declaration + 1, false, { declaration })
        end
    else
        -- Insert field declaration
        vim.api.nvim_buf_set_lines(bufnr, class_start, class_start, false, { declaration })
        inserted_new_field = true
    end

    -- Find current function scope (broader than just immediate scope)
    local function_start = M.find_function_start()
    local function_end = M.find_function_end()

    if function_start and function_end then
        -- Search entire function scope for occurrences
        -- Only offset by 1 if we inserted a new field, not if we updated an existing one
        local line_offset = inserted_new_field and 1 or 0
        local lines = vim.api.nvim_buf_get_lines(bufnr, function_start, function_end + line_offset, false)

        -- Find and replace all occurrences in the entire function
        for i, line in ipairs(lines) do
            local line_num = function_start + i - 1

            -- Skip the line we just inserted (if we inserted one)
            if not inserted_new_field or line_num ~= class_start then
                local new_line = line
                local count
                -- Use word boundary matching for numeric values to avoid partial replacements
                local escaped_value = vim.pesc(value)
                local field_replacement = '$this->' .. field_name:gsub('^%$', '')

                -- For numeric values, ensure we don't match partial numbers
                if value:match('^%d+$') then
                    -- It's a pure number, use digit boundary matching
                    local pattern = '(%D)' .. escaped_value .. '(%D)'
                    local replacement = '%1' .. field_replacement .. '%2'
                    new_line, count = new_line:gsub(pattern, replacement)

                    -- Check for number at start of line
                    if count == 0 then
                        local start_pattern = '^' .. escaped_value .. '(%D)'
                        local start_replacement = field_replacement .. '%1'
                        new_line, count = new_line:gsub(start_pattern, start_replacement)
                    end

                    -- Check for number at end of line
                    if count == 0 then
                        local end_pattern = '(%D)' .. escaped_value .. '$'
                        local end_replacement = '%1' .. field_replacement
                        new_line, count = new_line:gsub(end_pattern, end_replacement)
                    end
                else
                    -- For non-numeric values, use the original simple replacement
                    new_line, count = new_line:gsub(escaped_value, field_replacement)
                end

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    else
        -- Fallback to current scope if function boundaries can't be determined
        local scope_start, scope_end = M.find_current_scope()
        local line_offset = inserted_new_field and 1 or 0
        local lines = vim.api.nvim_buf_get_lines(bufnr, scope_start, scope_end + 1 + line_offset, false)

        for i, line in ipairs(lines) do
            local line_num = scope_start + i - 1

            if not inserted_new_field or line_num ~= class_start then
                local new_line = line
                local count
                -- Use word boundary matching for numeric values to avoid partial replacements
                local escaped_value = vim.pesc(value)
                local field_replacement = '$this->' .. field_name:gsub('^%$', '')

                -- For numeric values, ensure we don't match partial numbers
                if value:match('^%d+$') then
                    -- It's a pure number, use digit boundary matching
                    local pattern = '(%D)' .. escaped_value .. '(%D)'
                    local replacement = '%1' .. field_replacement .. '%2'
                    new_line, count = new_line:gsub(pattern, replacement)

                    -- Check for number at start of line
                    if count == 0 then
                        local start_pattern = '^' .. escaped_value .. '(%D)'
                        local start_replacement = field_replacement .. '%1'
                        new_line, count = new_line:gsub(start_pattern, start_replacement)
                    end

                    -- Check for number at end of line
                    if count == 0 then
                        local end_pattern = '(%D)' .. escaped_value .. '$'
                        local end_replacement = '%1' .. field_replacement
                        new_line, count = new_line:gsub(end_pattern, end_replacement)
                    end
                else
                    -- For non-numeric values, use the original simple replacement
                    new_line, count = new_line:gsub(escaped_value, field_replacement)
                end

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    end
end

-- Check if a field is already declared in the current class
function M.find_existing_field_declaration(field_name)
    local class_start = M.find_class_start()
    if not class_start then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(0, class_start, -1, false)
    local clean_field_name = field_name:gsub('^%$', '')

    for i, line in ipairs(lines) do
        -- Look for field declaration pattern (with or without value)
        if line:match('%s*private%s+%$' .. vim.pesc(clean_field_name) .. '%s*[;=]') or
            line:match('%s*protected%s+%$' .. vim.pesc(clean_field_name) .. '%s*[;=]') or
            line:match('%s*public%s+%$' .. vim.pesc(clean_field_name) .. '%s*[;=]') then
            return class_start + i - 1
        end
        -- Stop searching at the end of the class
        if line:match('^%s*}%s*$') then
            break
        end
    end

    return nil
end

-- Perform parameter extraction
function M.perform_extract_parameter(value, param_name, start_pos, end_pos)
    local conf = config.get()

    -- Find current function to add parameter to
    local function_start = M.find_function_start()
    if not function_start then
        ui.show_notification('Could not find function to add parameter to', 'error')
        return
    end

    -- Apply the refactoring
    M.apply_extract_parameter(value, param_name, start_pos, end_pos, function_start)
end

-- Apply parameter extraction changes
function M.apply_extract_parameter(value, param_name, start_pos, end_pos, function_start)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find the function declaration line and add parameter
    for i = function_start + 1, math.min(function_start + 5, #lines) do
        local line = lines[i]
        if line:match('function%s*%([^)]*%)') then
            local new_line = line:gsub('(%([^)]*)(%)?)', function(params, closing)
                if params == '(' then
                    return '(' .. param_name .. closing
                else
                    return params .. ', ' .. param_name .. closing
                end
            end)
            vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
            break
        end
    end

    -- Find current function scope and replace occurrences
    local function_end = M.find_function_end()

    if function_start and function_end then
        -- Search entire function scope for occurrences
        local lines = vim.api.nvim_buf_get_lines(bufnr, function_start, function_end + 1, false)

        -- Find and replace all occurrences in the entire function
        for i, line in ipairs(lines) do
            local line_num = function_start + i - 1

            -- Skip the function declaration line
            if not line:match('function%s*%([^)]*%)') then
                local new_line = line
                local count
                new_line, count = new_line:gsub(vim.pesc(value), param_name)

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    end
end

-- Multi-occurrence replacement (replaces all occurrences in current scope)
function M.apply_multi_occurrence_replacement(expression, var_name, insert_line, declaration, indent)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Check if this variable is already declared in the current scope
    local existing_declaration = M.find_existing_variable_declaration(var_name)
    if existing_declaration then
        -- Variable already exists, just do replacements without inserting declaration
    else
        -- Insert variable declaration
        vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, { indent .. declaration })
    end

    -- Find current function scope (broader than just immediate scope)
    local function_start = M.find_function_start()
    local function_end = M.find_function_end()

    if function_start and function_end then
        -- Search entire function scope for occurrences
        local line_offset = existing_declaration and 0 or 1
        local lines = vim.api.nvim_buf_get_lines(bufnr, function_start, function_end + line_offset, false)

        -- Find and replace all occurrences in the entire function
        for i, line in ipairs(lines) do
            local line_num = function_start + i - 1

            -- Skip the line we just inserted (if we inserted one)
            if existing_declaration or line_num ~= insert_line then
                local new_line = line
                local count
                new_line, count = new_line:gsub(vim.pesc(expression), var_name)

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    else
        -- Fallback to current scope if function boundaries can't be determined
        local scope_start, scope_end = M.find_current_scope()
        local line_offset = existing_declaration and 0 or 1
        local lines = vim.api.nvim_buf_get_lines(bufnr, scope_start, scope_end + 1 + line_offset, false)

        for i, line in ipairs(lines) do
            local line_num = scope_start + i - 1

            if existing_declaration or line_num ~= insert_line then
                local new_line = line
                local count
                new_line, count = new_line:gsub(vim.pesc(expression), var_name)

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    end

    -- Auto-format if enabled
    local conf = config.get()
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end
end

-- Check if a variable is already declared in the current scope
function M.find_existing_variable_declaration(var_name)
    local scope_start, scope_end = M.find_current_scope()
    local lines = vim.api.nvim_buf_get_lines(0, scope_start, scope_end + 1, false)

    for i, line in ipairs(lines) do
        -- Look for variable declaration pattern
        if line:match('%s*' .. vim.pesc(var_name) .. '%s*=') then
            return scope_start + i - 1
        end
    end

    return nil
end

-- Simple fallback variable extraction (single occurrence only)
function M.apply_simple_extract_variable(expression, var_name, start_pos, end_pos, insert_line, declaration, indent)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Insert variable declaration
    vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, { indent .. declaration })

    -- Replace only the originally selected expression
    if start_pos and end_pos then
        local adjusted_start_row = start_pos[1]
        local adjusted_end_row = end_pos[1]

        -- Adjust for inserted line
        if start_pos[1] >= insert_line then
            adjusted_start_row = adjusted_start_row + 1
            adjusted_end_row = adjusted_end_row + 1
        end

        -- Validate and replace
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if adjusted_start_row >= 0 and adjusted_start_row < #current_lines then
            local current_line = current_lines[adjusted_start_row + 1]

            if current_line and start_pos[2] >= 0 and end_pos[2] + 1 <= #current_line then
                local success, error_msg = pcall(function()
                    vim.api.nvim_buf_set_text(bufnr, adjusted_start_row, start_pos[2], adjusted_end_row, end_pos[2] + 1,
                        { var_name })
                end)

                if not success then
                    ui.show_notification('Warning: Could not replace original text', 'warn')
                end
            end
        end
    end

    -- Auto-format if enabled
    local conf = config.get()
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end
end

-- Perform constant extraction
function M.perform_extract_constant(value, const_name, start_pos, end_pos)
    local conf = config.get()

    -- Find class to add constant to
    local class_start = M.find_class_start()
    if not class_start then
        ui.show_notification('Could not find class to add constant to', 'error')
        return
    end

    local declaration = string.format('    const %s = %s;', const_name, value)

    -- Apply the refactoring immediately
    M.apply_extract_constant(value, const_name, start_pos, end_pos, class_start, declaration)
end

-- Apply constant extraction changes
function M.apply_extract_constant(value, const_name, start_pos, end_pos, class_start, declaration)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Check if this constant is already declared in the current scope
    local existing_declaration = M.find_existing_constant_declaration(const_name)
    if existing_declaration then
        -- Constant already exists, just do replacements without inserting declaration
    else
        -- Insert constant declaration
        vim.api.nvim_buf_set_lines(bufnr, class_start, class_start, false, { declaration })
    end

    -- Find current function scope (broader than just immediate scope)
    local function_start = M.find_function_start()
    local function_end = M.find_function_end()

    if function_start and function_end then
        -- Search entire function scope for occurrences
        local line_offset = existing_declaration and 0 or 1
        local lines = vim.api.nvim_buf_get_lines(bufnr, function_start, function_end + line_offset, false)

        -- Find and replace all occurrences in the entire function
        for i, line in ipairs(lines) do
            local line_num = function_start + i - 1

            -- Skip the line we just inserted (if we inserted one)
            if existing_declaration or line_num ~= class_start then
                local new_line = line
                local count
                new_line, count = new_line:gsub(vim.pesc(value), 'self::' .. const_name)

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    else
        -- Fallback to current scope if function boundaries can't be determined
        local scope_start, scope_end = M.find_current_scope()
        local line_offset = existing_declaration and 0 or 1
        local lines = vim.api.nvim_buf_get_lines(bufnr, scope_start, scope_end + 1 + line_offset, false)

        for i, line in ipairs(lines) do
            local line_num = scope_start + i - 1

            if existing_declaration or line_num ~= class_start then
                local new_line = line
                local count
                new_line, count = new_line:gsub(vim.pesc(value), 'self::' .. const_name)

                if count > 0 then
                    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
                end
            end
        end
    end
end

-- Check if a constant is already declared in the current class
function M.find_existing_constant_declaration(const_name)
    local class_start = M.find_class_start()
    if not class_start then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(0, class_start, -1, false)

    for i, line in ipairs(lines) do
        -- Look for constant declaration pattern
        if line:match('%s*const%s+' .. vim.pesc(const_name) .. '%s*=') then
            return class_start + i - 1
        end
        -- Stop searching at the end of the class
        if line:match('^%s*}%s*$') then
            break
        end
    end

    return nil
end

-- Helper functions for name generation
function M.generate_variable_name(expression)
    -- Simple heuristics for generating variable names
    local clean = expression:gsub('[^%w_]', ''):lower()

    if clean:match('^get') then
        return clean:gsub('^get', '')
    elseif clean:match('name') then
        return 'name'
    elseif clean:match('id') then
        return 'id'
    elseif clean:match('count') then
        return 'count'
    else
        return 'value'
    end
end

function M.generate_constant_name(value)
    if value:match('^%d+$') then
        return 'DEFAULT_VALUE'
    elseif value:match('^".*"$') or value:match("^'.*'$") then
        local content = value:sub(2, -2):upper():gsub('[^%w]', '_')
        return content ~= '' and content or 'DEFAULT_STRING'
    else
        return 'DEFAULT_CONSTANT'
    end
end

function M.generate_field_name(value)
    return M.generate_variable_name(value)
end

function M.generate_parameter_name(value)
    return M.generate_variable_name(value)
end

-- Helper functions for positioning
function M.find_variable_insert_position()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1] - 1

    -- Find the outermost scope that contains all potential usages
    local function_start = M.find_function_start()
    if function_start then
        -- Look for the first executable line after the function declaration
        local lines = vim.api.nvim_buf_get_lines(0, function_start, current_line + 10, false)

        for i, line in ipairs(lines) do
            local line_num = function_start + i - 1
            -- Skip function declaration, opening brace, and empty lines
            if not line:match('^%s*$') and
                not line:match('function%s*%(') and
                not line:match('^%s*{%s*$') and
                not line:match('^%s*public%s+function') and
                not line:match('^%s*private%s+function') and
                not line:match('^%s*protected%s+function') then
                -- This is the first executable line in the function
                return line_num
            end
        end
    end

    -- Fallback: look backwards for a good insertion point
    local lines = vim.api.nvim_buf_get_lines(0, 0, current_line + 1, false)

    for i = current_line, 1, -1 do
        local line = lines[i]

        -- Skip empty lines and comments
        if line:match('^%s*$') or line:match('^%s*//') or line:match('^%s*%*') or line:match('^%s*/%*') then
            -- Continue searching
        elseif line:match('%$%w+%s*=') then
            -- Found a variable declaration, insert after this line
            return i
        elseif line:match('^%s*{') or line:match('function%s*%(') or line:match('%)%s*{') then
            -- Found function opening brace, insert after this line
            return i
        end
    end

    -- If no good position found, insert at current line
    return current_line
end

-- Find the start of the current function/method
function M.find_function_start()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1] - 1
    local lines = vim.api.nvim_buf_get_lines(0, 0, current_line + 1, false)

    for i = current_line, 1, -1 do
        local line = lines[i]
        if line:match('%s*function%s+') or
            line:match('%s*public%s+function%s+') or
            line:match('%s*private%s+function%s+') or
            line:match('%s*protected%s+function%s+') then
            return i - 1 -- Return 0-based index
        end
    end

    return nil
end

function M.find_class_start()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        if line:match('^%s*class%s+') then
            -- Look for opening brace on this line or following lines
            if line:match('{') then
                -- Opening brace is on the same line as class declaration
                -- ipairs gives 1-based index, add 1 to insert after the brace
                return i + 1 -- This will insert after the line with the brace
            else
                -- Look for opening brace on subsequent lines
                for j = i + 1, math.min(i + 5, #lines) do
                    if lines[j]:match('{') then
                        -- ipairs gives 1-based index, add 1 to insert after the brace
                        return j + 1 -- This will insert after the line with the brace
                    end
                end
            end
        end
    end

    return nil
end

function M.get_current_indentation(line_num)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local line = lines[line_num + 1] or ''
    return line:match('^%s*') or ''
end

-- Find the current scope (method, function, or class)
function M.find_current_scope()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1] - 1
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local scope_start = 0
    local scope_end = #lines - 1
    local brace_count = 0
    local found_start = false

    -- Look backwards for the start of current method/function
    for i = current_line, 1, -1 do
        local line = lines[i]

        -- Count braces
        local open_braces = select(2, line:gsub('{', ''))
        local close_braces = select(2, line:gsub('}', ''))
        brace_count = brace_count - open_braces + close_braces

        -- If we find a function/method declaration and we're at brace level 0
        if brace_count == 0 and (line:match('%s*function%s+') or line:match('%s*public%s+function%s+') or
                line:match('%s*private%s+function%s+') or line:match('%s*protected%s+function%s+')) then
            scope_start = i - 1 -- Convert to 0-based
            found_start = true
            break
        end
    end

    -- If no function found, use class scope
    if not found_start then
        for i = current_line, 1, -1 do
            local line = lines[i]
            if line:match('%s*class%s+') then
                scope_start = i - 1
                break
            end
        end
    end

    -- Look forward for the end of current scope
    brace_count = 0
    for i = scope_start + 1, #lines do
        local line = lines[i]

        local open_braces = select(2, line:gsub('{', ''))
        local close_braces = select(2, line:gsub('}', ''))
        brace_count = brace_count + open_braces - close_braces

        -- If we're back at level 0 after going into the scope
        if brace_count < 0 then
            scope_end = i - 1
            break
        end
    end

    return scope_start, scope_end
end

-- Find the end of the current function/method
function M.find_function_end()
    local function_start = M.find_function_start()
    if not function_start then
        return nil
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local brace_count = 0
    local found_opening = false

    -- Start from function start and find the matching closing brace
    for i = function_start + 1, #lines do
        local line = lines[i]

        local open_braces = select(2, line:gsub('{', ''))
        local close_braces = select(2, line:gsub('}', ''))

        if not found_opening and open_braces > 0 then
            found_opening = true
            brace_count = open_braces
        elseif found_opening then
            brace_count = brace_count + open_braces - close_braces

            if brace_count <= 0 then
                return i - 1 -- Return 0-based index
            end
        end
    end

    return #lines - 1 -- Fallback to end of file
end

return M
