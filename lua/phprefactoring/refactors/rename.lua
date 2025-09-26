-- Rename refactoring module
-- Handles variable, method, and class renaming

local parser = require('phprefactoring.parser')
local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}

-- Rename variable
function M.variable()
    local selection, start_pos, end_pos = parser.get_visual_selection()
    local variable_text = ''
    local variable_node = nil

    if selection and #selection > 0 then
        variable_text = table.concat(selection, '\n')
        -- start_pos and end_pos are already set from get_visual_selection()
    else
        -- Try to get variable under cursor
        local node = parser.get_current_node()
        if node then
            -- Check if current node is a variable
            if M.is_variable_node(node) then
                variable_text = parser.get_node_text(node)
                variable_node = node
                local start_row, start_col, end_row, end_col = node:range()
                start_pos = { start_row, start_col }
                end_pos = { end_row, end_col }
            else
                -- Try to find a parent variable node
                local current = node:parent()
                while current do
                    if M.is_variable_node(current) then
                        variable_text = parser.get_node_text(current)
                        variable_node = current
                        local start_row, start_col, end_row, end_col = current:range()
                        start_pos = { start_row, start_col }
                        end_pos = { end_row, end_col }
                        break
                    end
                    current = current:parent()
                end
            end
        end
    end

    if variable_text == '' then
        ui.show_notification('No variable found under cursor. Try selecting the variable first.', 'warn')
        return
    end

    -- Validate it's a PHP variable
    if not M.is_php_variable(variable_text) then
        ui.show_notification('Selected text is not a valid PHP variable.', 'warn')
        return
    end

    -- Extract the variable name without the $ prefix for suggestion
    local current_name = variable_text:gsub('^%$', '')

    ui.show_input({
        title = 'Rename Variable',
        prompt = 'New variable name: $',
        default = current_name,
        width = 40
    }, function(new_name)
        if new_name and new_name ~= '' and new_name ~= current_name then
            M.perform_rename_variable(variable_text, '$' .. new_name, start_pos, end_pos)
        end
    end)
end

-- Rename method/function
function M.method()
    local method_info = M.get_method_under_cursor()

    if not method_info then
        ui.show_notification('No method found under cursor.', 'warn')
        return
    end

    local current_name = method_info.name

    ui.show_input({
        title = 'Rename Method',
        prompt = 'New method name: ',
        default = current_name,
        width = 40
    }, function(new_name)
        if new_name and new_name ~= '' and new_name ~= current_name then
            if M.is_valid_method_name(new_name) then
                M.perform_rename_method(method_info, new_name)
            else
                ui.show_notification('Invalid method name. Must be a valid PHP identifier.', 'error')
            end
        end
    end)
end

-- Rename class
function M.class()
    local class_info = M.get_class_under_cursor()

    if not class_info then
        ui.show_notification('No class found under cursor.', 'warn')
        return
    end

    local current_name = class_info.name

    ui.show_input({
        title = 'Rename Class',
        prompt = 'New class name: ',
        default = current_name,
        width = 40
    }, function(new_name)
        if new_name and new_name ~= '' and new_name ~= current_name then
            if M.is_valid_class_name(new_name) then
                M.perform_rename_class(class_info, new_name)
            else
                ui.show_notification('Invalid class name. Must be a valid PHP identifier starting with uppercase.', 'error')
            end
        end
    end)
end

-- Check if a node represents a variable
function M.is_variable_node(node)
    if not node then
        return false
    end

    local variable_types = {
        'variable_name',
        'simple_parameter',
        'variadic_parameter'
    }

    return vim.tbl_contains(variable_types, node:type())
end

-- Check if text is a valid PHP variable (enhanced)
function M.is_php_variable(text)
    if not text or text == '' then
        return false
    end

    -- PHP variables must start with $ and contain valid identifier characters
    if not text:match('^%$[a-zA-Z_][a-zA-Z0-9_]*$') then
        return false
    end

    -- Additional checks for reserved variables/keywords
    local reserved_vars = {
        '$this', '$GLOBALS', '$_SERVER', '$_GET', '$_POST', '$_FILES',
        '$_COOKIE', '$_SESSION', '$_REQUEST', '$_ENV', '$argv', '$argc'
    }

    for _, reserved in ipairs(reserved_vars) do
        if text == reserved then
            return false -- Don't allow renaming reserved variables
        end
    end

    return true
end

-- Check if text is a valid PHP method name
function M.is_valid_method_name(name)
    if not name or name == '' then
        return false
    end

    -- PHP method names must be valid identifiers
    if not name:match('^[a-zA-Z_][a-zA-Z0-9_]*$') then
        return false
    end

    -- Check for reserved method names and PHP keywords
    local reserved_methods = {
        '__construct', '__destruct', '__call', '__callStatic', '__get', '__set',
        '__isset', '__unset', '__sleep', '__wakeup', '__toString', '__invoke',
        '__set_state', '__clone', '__debugInfo', '__serialize', '__unserialize'
    }

    local php_keywords = {
        'abstract', 'and', 'array', 'as', 'break', 'callable', 'case', 'catch',
        'class', 'clone', 'const', 'continue', 'declare', 'default', 'die', 'do',
        'echo', 'else', 'elseif', 'empty', 'enddeclare', 'endfor', 'endforeach',
        'endif', 'endswitch', 'endwhile', 'eval', 'exit', 'extends', 'final',
        'finally', 'fn', 'for', 'foreach', 'function', 'global', 'goto', 'if',
        'implements', 'include', 'include_once', 'instanceof', 'insteadof',
        'interface', 'isset', 'list', 'namespace', 'new', 'or', 'print',
        'private', 'protected', 'public', 'require', 'require_once', 'return',
        'static', 'switch', 'throw', 'trait', 'try', 'unset', 'use', 'var',
        'while', 'xor', 'yield', 'yield_from'
    }

    -- Allow magic methods but warn about reserved keywords
    for _, keyword in ipairs(php_keywords) do
        if name:lower() == keyword then
            return false
        end
    end

    return true
end

-- Check if text is a valid PHP class name
function M.is_valid_class_name(name)
    if not name or name == '' then
        return false
    end

    -- PHP class names must be valid identifiers
    if not name:match('^[a-zA-Z_][a-zA-Z0-9_]*$') then
        return false
    end

    -- Class names should start with uppercase (PSR-1 convention)
    if not name:match('^[A-Z]') then
        return false
    end

    -- Check for PHP keywords that can't be class names
    local reserved_keywords = {
        'Abstract', 'And', 'Array', 'As', 'Break', 'Callable', 'Case', 'Catch',
        'Class', 'Clone', 'Const', 'Continue', 'Declare', 'Default', 'Die', 'Do',
        'Echo', 'Else', 'Elseif', 'Empty', 'Enddeclare', 'Endfor', 'Endforeach',
        'Endif', 'Endswitch', 'Endwhile', 'Eval', 'Exit', 'Extends', 'Final',
        'Finally', 'Fn', 'For', 'Foreach', 'Function', 'Global', 'Goto', 'If',
        'Implements', 'Include', 'Include_once', 'Instanceof', 'Insteadof',
        'Interface', 'Isset', 'List', 'Namespace', 'New', 'Or', 'Print',
        'Private', 'Protected', 'Public', 'Require', 'Require_once', 'Return',
        'Static', 'Switch', 'Throw', 'Trait', 'Try', 'Unset', 'Use', 'Var',
        'While', 'Xor', 'Yield', 'Yield_from'
    }

    for _, keyword in ipairs(reserved_keywords) do
        if name == keyword then
            return false
        end
    end

    return true
end

-- Get method information under cursor
function M.get_method_under_cursor()
    local node = parser.get_current_node()
    if not node then
        return nil
    end

    -- Find method declaration node
    local current = node
    while current do
        local node_type = current:type()
        if vim.tbl_contains({'method_declaration', 'function_definition'}, node_type) then
            -- Extract method name
            for child in current:iter_children() do
                if child:type() == 'name' then
                    local method_name = parser.get_node_text(child)
                    local start_row, start_col, end_row, end_col = child:range()
                    return {
                        name = method_name,
                        node = current,
                        name_node = child,
                        start_pos = { start_row, start_col },
                        end_pos = { end_row, end_col }
                    }
                end
            end
        end
        current = current:parent()
    end

    return nil
end

-- Get class information under cursor
function M.get_class_under_cursor()
    local node = parser.get_current_node()
    if not node then
        return nil
    end

    -- Find class declaration node
    local current = node
    while current do
        if current:type() == 'class_declaration' then
            -- Extract class name
            for child in current:iter_children() do
                if child:type() == 'name' then
                    local class_name = parser.get_node_text(child)
                    local start_row, start_col, end_row, end_col = child:range()
                    return {
                        name = class_name,
                        node = current,
                        name_node = child,
                        start_pos = { start_row, start_col },
                        end_pos = { end_row, end_col }
                    }
                end
            end
        end
        current = current:parent()
    end

    return nil
end

-- Perform variable rename
function M.perform_rename_variable(old_variable, new_variable, start_pos, end_pos)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Find the scope for the rename operation using TreeSitter
    local scope_node = parser.get_current_scope()
    local scope_start, scope_end = nil, nil

    if scope_node then
        local start_row, start_col, end_row, end_col = scope_node:range()
        scope_start = start_row
        scope_end = end_row

        -- If we're in a method/function, use that scope
        local scope_type = scope_node:type()
        if not (scope_type == 'function_definition' or scope_type == 'method_declaration') then
            -- If current scope is not a function/method, try to find containing function
            local current = scope_node:parent()
            while current do
                local current_type = current:type()
                if current_type == 'function_definition' or current_type == 'method_declaration' then
                    local func_start_row, func_start_col, func_end_row, func_end_col = current:range()
                    scope_start = func_start_row
                    scope_end = func_end_row
                    scope_node = current
                    break
                end
                current = current:parent()
            end
        end
    end

    if not scope_start or not scope_end then
        ui.show_notification('Could not determine variable scope - variable must be within a function or method', 'error')
        return
    end

    -- Find all occurrences of the variable in scope
    local occurrences = M.find_variable_occurrences(old_variable, scope_start, scope_end)

    if #occurrences == 0 then
        ui.show_notification('No occurrences of variable found in scope', 'warn')
        return
    end

    -- Apply the renaming (process in reverse order to maintain positions)
    table.sort(occurrences, function(a, b)
        if a.line == b.line then
            return a.col > b.col
        end
        return a.line > b.line
    end)

    local changes_made = 0
    for _, occurrence in ipairs(occurrences) do
        local line_content = vim.api.nvim_buf_get_lines(bufnr, occurrence.line, occurrence.line + 1, false)[1]
        if line_content then
            local before = line_content:sub(1, occurrence.col)
            local after = line_content:sub(occurrence.col + #old_variable + 1)
            local new_line = before .. new_variable .. after

            vim.api.nvim_buf_set_lines(bufnr, occurrence.line, occurrence.line + 1, false, { new_line })
            changes_made = changes_made + 1
        end
    end

    -- Auto-format if enabled
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end

    ui.show_notification(string.format('Renamed variable in %d locations', changes_made), 'info')
end

-- Perform method rename
function M.perform_rename_method(method_info, new_name)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Get the scope for method renaming (current class)
    local scope_node = parser.get_current_scope()
    local scope_start, scope_end = nil, nil

    if scope_node then
        local current = scope_node
        -- Find the containing class for method renaming
        while current do
            local current_type = current:type()
            if current_type == 'class_declaration' then
                local class_start_row, class_start_col, class_end_row, class_end_col = current:range()
                scope_start = class_start_row
                scope_end = class_end_row
                break
            end
            current = current:parent()
        end
    end

    -- Find all occurrences of the method in the determined scope
    local occurrences
    if scope_start and scope_end then
        occurrences = M.find_method_occurrences_in_scope(method_info.name, scope_start, scope_end)
    else
        -- Fallback to current file if no specific scope found
        occurrences = M.find_method_occurrences(method_info.name)
    end

    if #occurrences == 0 then
        ui.show_notification('No occurrences of method found', 'warn')
        return
    end

    -- Apply the renaming (process in reverse order to maintain positions)
    table.sort(occurrences, function(a, b)
        if a.line == b.line then
            return a.col > b.col
        end
        return a.line > b.line
    end)

    local changes_made = 0
    for _, occurrence in ipairs(occurrences) do
        local line_content = vim.api.nvim_buf_get_lines(bufnr, occurrence.line, occurrence.line + 1, false)[1]
        if line_content then
            local before = line_content:sub(1, occurrence.col)
            local after = line_content:sub(occurrence.col + #method_info.name + 1)
            local new_line = before .. new_name .. after

            vim.api.nvim_buf_set_lines(bufnr, occurrence.line, occurrence.line + 1, false, { new_line })
            changes_made = changes_made + 1
        end
    end

    -- Auto-format if enabled
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end

    ui.show_notification(string.format('Renamed method in %d locations', changes_made), 'info')
end

-- Perform class rename
function M.perform_rename_class(class_info, new_name)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Find all occurrences of the class in current file
    local occurrences = M.find_class_occurrences(class_info.name)

    if #occurrences == 0 then
        ui.show_notification('No occurrences of class found', 'warn')
        return
    end

    -- Apply the renaming (process in reverse order to maintain positions)
    table.sort(occurrences, function(a, b)
        if a.line == b.line then
            return a.col > b.col
        end
        return a.line > b.line
    end)

    local changes_made = 0
    for _, occurrence in ipairs(occurrences) do
        local line_content = vim.api.nvim_buf_get_lines(bufnr, occurrence.line, occurrence.line + 1, false)[1]
        if line_content then
            local before = line_content:sub(1, occurrence.col)
            local after = line_content:sub(occurrence.col + #class_info.name + 1)
            local new_line = before .. new_name .. after

            vim.api.nvim_buf_set_lines(bufnr, occurrence.line, occurrence.line + 1, false, { new_line })
            changes_made = changes_made + 1
        end
    end

    -- Auto-format if enabled
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end

    -- Handle file renaming if appropriate
    local file_renamed = M.rename_class_file(class_info.name, new_name)

    local message = string.format('Renamed class in %d locations', changes_made)
    if file_renamed then
        message = message .. ' and updated file name'
    end

    ui.show_notification(message, 'info')
end


-- Find all occurrences of a variable in the specified range using TreeSitter
function M.find_variable_occurrences(variable_name, start_line, end_line)
    local bufnr = vim.api.nvim_get_current_buf()
    local occurrences = {}

    -- Try to use TreeSitter for more accurate variable detection
    if parser.has_treesitter then
        local ts_parser = vim.treesitter.get_parser(bufnr, 'php')
        if ts_parser then
            local tree = ts_parser:parse()[1]
            if tree then
                local root = tree:root()

                -- Query for variable nodes in the scope range
                local function traverse_node(node)
                    local start_row, start_col, end_row, end_col = node:range()

                    -- Skip nodes outside our scope
                    if end_row < start_line or start_row > end_line then
                        return
                    end

                    -- Check if this is a variable node
                    if node:type() == 'variable_name' then
                        local node_text = parser.get_node_text(node)
                        if node_text == variable_name then
                            table.insert(occurrences, {
                                line = start_row,
                                col = start_col,
                                text = variable_name
                            })
                        end
                    end

                    -- Recursively check children
                    for child in node:iter_children() do
                        traverse_node(child)
                    end
                end

                traverse_node(root)
                return occurrences
            end
        end
    end

    -- Fallback to regex-based approach if TreeSitter is not available
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    local escaped_var = vim.pesc(variable_name)

    for i, line in ipairs(lines) do
        local line_num = start_line + i - 1

        -- Skip lines that are comments or inside strings (basic filtering)
        local cleaned_line = M.remove_string_literals_and_comments(line)

        local start_col = 1

        while true do
            local col = cleaned_line:find(escaped_var, start_col)
            if not col then
                break
            end

            -- Check that it's a whole word (variable name)
            local before_char = col > 1 and cleaned_line:sub(col - 1, col - 1) or ''
            local after_char = cleaned_line:sub(col + #variable_name, col + #variable_name)

            -- Enhanced validation for proper variable usage
            if M.is_valid_variable_occurrence(cleaned_line, col, variable_name, before_char, after_char) then
                -- Get the actual position in the original line
                local actual_col = M.find_actual_position_in_original_line(line, cleaned_line, col)
                if actual_col then
                    table.insert(occurrences, {
                        line = line_num,
                        col = actual_col - 1, -- Convert to 0-based
                        text = variable_name
                    })
                end
            end

            start_col = col + 1
        end
    end

    return occurrences
end

-- Find all occurrences of a method in a specific scope
function M.find_method_occurrences_in_scope(method_name, start_line, end_line)
    local bufnr = vim.api.nvim_get_current_buf()
    local occurrences = {}

    -- Try to use TreeSitter for more accurate method detection
    if parser.has_treesitter then
        local ts_parser = vim.treesitter.get_parser(bufnr, 'php')
        if ts_parser then
            local tree = ts_parser:parse()[1]
            if tree then
                local root = tree:root()

                -- Query for method-related nodes in the scope range
                local function traverse_node(node)
                    local start_row, start_col, end_row, end_col = node:range()

                    -- Skip nodes outside our scope
                    if end_row < start_line or start_row > end_line then
                        return
                    end

                    -- Check if this is a method-related node
                    local node_type = node:type()
                    if node_type == 'name' and node:parent() then
                        local parent_type = node:parent():type()
                        if parent_type == 'method_declaration' or
                           parent_type == 'function_call_expression' or
                           parent_type == 'member_call_expression' then
                            local node_text = parser.get_node_text(node)
                            if node_text == method_name then
                                table.insert(occurrences, {
                                    line = start_row,
                                    col = start_col,
                                    text = method_name
                                })
                            end
                        end
                    end

                    -- Recursively check children
                    for child in node:iter_children() do
                        traverse_node(child)
                    end
                end

                traverse_node(root)
                return occurrences
            end
        end
    end

    -- Fallback to regex-based approach if TreeSitter is not available
    return M.find_method_occurrences_regex(method_name, start_line, end_line)
end

-- Find all occurrences of a method in the current file using TreeSitter
function M.find_method_occurrences(method_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return M.find_method_occurrences_in_scope(method_name, 0, #lines - 1)
end

-- Regex-based method occurrence finder (fallback)
function M.find_method_occurrences_regex(method_name, start_line, end_line)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    local occurrences = {}

    local escaped_method = vim.pesc(method_name)

    for i, line in ipairs(lines) do
        local line_num = start_line + i - 1

        -- Remove string literals and comments for safer parsing
        local cleaned_line = M.remove_string_literals_and_comments(line)

        local start_col = 1

        while true do
            local col = cleaned_line:find(escaped_method, start_col)
            if not col then
                break
            end

            -- Enhanced method occurrence validation
            if M.is_valid_method_occurrence(cleaned_line, col, method_name) then
                -- Get the actual position in the original line
                local actual_col = M.find_actual_position_in_original_line(line, cleaned_line, col)
                if actual_col then
                    table.insert(occurrences, {
                        line = line_num,
                        col = actual_col - 1, -- Convert to 0-based
                        text = method_name
                    })
                end
            end

            start_col = col + 1
        end
    end

    return occurrences
end

-- Find all occurrences of a class in the current file using TreeSitter
function M.find_class_occurrences(class_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local occurrences = {}

    -- Try to use TreeSitter for more accurate class detection
    if parser.has_treesitter then
        local ts_parser = vim.treesitter.get_parser(bufnr, 'php')
        if ts_parser then
            local tree = ts_parser:parse()[1]
            if tree then
                local root = tree:root()

                -- Query for class-related nodes in the entire file
                local function traverse_node(node)
                    -- Check if this is a class-related node
                    local node_type = node:type()
                    if node_type == 'name' and node:parent() then
                        local parent_type = node:parent():type()
                        -- Look for class declarations, instantiations, static calls, etc.
                        if parent_type == 'class_declaration' or
                           parent_type == 'object_creation_expression' or
                           parent_type == 'scoped_call_expression' or
                           parent_type == 'class_constant_access_expression' or
                           parent_type == 'instanceof_expression' or
                           parent_type == 'base_clause' or  -- extends
                           parent_type == 'class_interface_clause' then  -- implements
                            local node_text = parser.get_node_text(node)
                            if node_text == class_name then
                                local start_row, start_col, end_row, end_col = node:range()
                                table.insert(occurrences, {
                                    line = start_row,
                                    col = start_col,
                                    text = class_name
                                })
                            end
                        end
                    elseif node_type == 'qualified_name' then
                        -- Handle namespaced class names
                        local node_text = parser.get_node_text(node)
                        if node_text:match(class_name .. '$') then  -- Ends with our class name
                            local start_row, start_col, end_row, end_col = node:range()
                            -- Find the exact position of the class name within the qualified name
                            local class_start = node_text:find(class_name .. '$')
                            if class_start then
                                table.insert(occurrences, {
                                    line = start_row,
                                    col = start_col + class_start - 1,
                                    text = class_name
                                })
                            end
                        end
                    end

                    -- Recursively check children
                    for child in node:iter_children() do
                        traverse_node(child)
                    end
                end

                traverse_node(root)
                return occurrences
            end
        end
    end

    -- Fallback to regex-based approach if TreeSitter is not available
    return M.find_class_occurrences_regex(class_name)
end

-- Regex-based class occurrence finder (fallback)
function M.find_class_occurrences_regex(class_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local occurrences = {}

    local escaped_class = vim.pesc(class_name)

    for i, line in ipairs(lines) do
        local line_num = i - 1

        -- Remove string literals and comments for safer parsing
        local cleaned_line = M.remove_string_literals_and_comments(line)

        local start_col = 1

        while true do
            local col = cleaned_line:find(escaped_class, start_col)
            if not col then
                break
            end

            -- Enhanced class occurrence validation
            if M.is_valid_class_occurrence(cleaned_line, col, class_name) then
                -- Get the actual position in the original line
                local actual_col = M.find_actual_position_in_original_line(line, cleaned_line, col)
                if actual_col then
                    table.insert(occurrences, {
                        line = line_num,
                        col = actual_col - 1, -- Convert to 0-based
                        text = class_name
                    })
                end
            end

            start_col = col + 1
        end
    end

    return occurrences
end

-- Rename class file if it matches the class name
function M.rename_class_file(old_class_name, new_class_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(bufnr)

    if current_file == '' then
        return false
    end

    -- Extract current file name and directory
    local file_dir = vim.fn.fnamemodify(current_file, ':h')
    local file_name = vim.fn.fnamemodify(current_file, ':t:r') -- filename without extension
    local file_ext = vim.fn.fnamemodify(current_file, ':e')    -- extension

    -- Check if current file name matches the old class name (case-insensitive)
    if file_name:lower() ~= old_class_name:lower() then
        return false -- File name doesn't match class name, don't rename
    end

    -- Construct new file path
    local new_file_path = file_dir .. '/' .. new_class_name .. '.' .. file_ext

    -- Check if target file already exists
    if vim.fn.filereadable(new_file_path) == 1 then
        ui.show_notification('Target file already exists: ' .. new_file_path, 'warn')
        return false
    end

    -- Save current buffer
    local success = pcall(vim.cmd, 'write')
    if not success then
        ui.show_notification('Failed to save current file before renaming', 'error')
        return false
    end

    -- Attempt to rename the file using vim's rename functionality
    local rename_success = pcall(function()
        -- Close current buffer without deleting it
        local buf_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        -- Create new file with the content
        vim.cmd('edit ' .. vim.fn.fnameescape(new_file_path))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, buf_content)
        vim.cmd('write')

        -- Delete old file if the new one was created successfully
        if vim.fn.filereadable(new_file_path) == 1 then
            vim.fn.delete(current_file)
        end
    end)

    if not rename_success then
        ui.show_notification('Failed to rename file', 'error')
        return false
    end

    return true
end

-- Enhanced validation for method occurrences
function M.is_valid_method_occurrence(line, col, method_name)
    local before_char = col > 1 and line:sub(col - 1, col - 1) or ''
    local after_char = line:sub(col + #method_name, col + #method_name)

    -- Must be word-bounded
    if (before_char ~= '' and before_char:match('[%w_]')) or
       (after_char ~= '' and after_char:match('[%w_]')) then
        return false
    end

    -- Get broader context for pattern matching
    local context_before = col > 20 and line:sub(col - 20, col - 1) or line:sub(1, col - 1)
    local context_after = line:sub(col + #method_name, col + #method_name + 10)

    -- Method declaration patterns (enhanced)
    if context_before:match('%s+function%s*$') or                    -- function methodName
       context_before:match('public%s+function%s*$') or              -- public function methodName
       context_before:match('private%s+function%s*$') or             -- private function methodName
       context_before:match('protected%s+function%s*$') or           -- protected function methodName
       context_before:match('static%s+function%s*$') or              -- static function methodName
       context_before:match('abstract%s+function%s*$') or            -- abstract function methodName
       context_before:match('final%s+function%s*$') or               -- final function methodName
       context_before:match('public%s+static%s+function%s*$') or     -- public static function methodName
       context_before:match('private%s+static%s+function%s*$') or    -- private static function methodName
       context_before:match('protected%s+static%s+function%s*$') or  -- protected static function methodName
       context_before:match('static%s+public%s+function%s*$') or     -- static public function methodName
       context_before:match('static%s+private%s+function%s*$') or    -- static private function methodName
       context_before:match('static%s+protected%s+function%s*$') then -- static protected function methodName
        return true
    end

    -- Method call patterns (enhanced)
    if context_before:match('->%s*$') or                             -- $obj->methodName
       context_before:match('::%s*$') then                          -- Class::methodName
        return true
    end

    -- Function call patterns (enhanced)
    if after_char == '(' and col > 1 then
        -- Check it's not a variable or other construct
        if not context_before:match('%$[%w_]*$') and                 -- Not $variableMethodName
           not context_before:match('class%s*$') and                 -- Not class methodName
           not context_before:match('const%s*$') and                 -- Not const methodName
           not context_before:match('new%s*$') then                  -- Not new methodName
            return true
        end
    end

    -- Callable patterns
    if context_before:match("'%s*$") and context_after:match("^%s*'") then  -- 'methodName'
        return true
    end
    if context_before:match('"%s*$') and context_after:match('^%s*"') then  -- "methodName"
        return true
    end

    -- Array callable patterns
    if context_before:match('%[%s*$') and context_after:match('^%s*%]') then -- [methodName]
        return true
    end

    -- Reflection/dynamic call patterns
    if context_before:match('call_user_func%s*%(%s*$') or           -- call_user_func(methodName
       context_before:match('is_callable%s*%(%s*$') or             -- is_callable(methodName
       context_before:match('method_exists%s*%([^,]*,%s*$') then   -- method_exists($obj, methodName
        return true
    end

    return false
end

-- Enhanced validation for class occurrences
function M.is_valid_class_occurrence(line, col, class_name)
    local before_char = col > 1 and line:sub(col - 1, col - 1) or ''
    local after_char = line:sub(col + #class_name, col + #class_name)

    -- Must be word-bounded
    if (before_char ~= '' and before_char:match('[%w_\\]')) or
       (after_char ~= '' and after_char:match('[%w_]')) then
        return false
    end

    -- Get broader context for pattern matching
    local context_before = col > 30 and line:sub(col - 30, col - 1) or line:sub(1, col - 1)
    local context_after = line:sub(col + #class_name, col + #class_name + 20)

    -- Class declaration patterns (enhanced)
    if context_before:match('%s+class%s*$') or                       -- class ClassName
       context_before:match('abstract%s+class%s*$') or               -- abstract class ClassName
       context_before:match('final%s+class%s*$') then                -- final class ClassName
        return true
    end

    -- Inheritance patterns (enhanced)
    if context_before:match('%s+extends%s*$') or                     -- extends ClassName
       context_before:match('%s+implements%s*$') or                  -- implements ClassName
       context_before:match(',%s*$') and
       context_before:match('implements.*,%s*$') then                -- implements Interface1, ClassName
        return true
    end

    -- Instantiation patterns (enhanced)
    if context_before:match('%s+new%s*$') or                         -- new ClassName
       context_before:match('=%s*new%s*$') or                        -- = new ClassName
       context_before:match('return%s+new%s*$') then                 -- return new ClassName
        return true
    end

    -- Static access patterns (enhanced)
    if after_char == ':' and context_after:match('^::') then         -- ClassName::
        return true
    end

    -- Type hints and declarations (enhanced)
    if context_before:match('%(%s*$') or                             -- function(ClassName
       context_before:match(',%s*$') or                              -- function($param, ClassName
       context_before:match(':%s*$') or                              -- function(): ClassName
       context_before:match('|%s*$') or                              -- Type1|ClassName
       context_before:match('&%s*$') then                            -- Type1&ClassName
        return true
    end

    -- DocBlock and annotations (enhanced)
    if context_before:match('@param%s+$') or                         -- @param ClassName
       context_before:match('@return%s+$') or                        -- @return ClassName
       context_before:match('@var%s+$') or                           -- @var ClassName
       context_before:match('@throws%s+$') or                        -- @throws ClassName
       context_before:match('@see%s+$') then                         -- @see ClassName
        return true
    end

    -- instanceof patterns
    if context_before:match('instanceof%s*$') then                   -- instanceof ClassName
        return true
    end

    -- Reflection patterns (enhanced)
    if context_before:match('ReflectionClass%s*%(%s*$') or           -- new ReflectionClass(ClassName
       context_before:match('class_exists%s*%(%s*$') or              -- class_exists(ClassName
       context_before:match('is_subclass_of%s*%([^,]*,%s*$') or      -- is_subclass_of($obj, ClassName
       context_before:match('get_parent_class%s*%(%s*$') then        -- get_parent_class(ClassName
        return true
    end

    -- Use statements and namespaces (enhanced)
    if context_before:match('use%s*$') or                            -- use ClassName
       context_before:match('use%s+[^;]*\\%s*$') or                  -- use Namespace\ClassName
       context_before:match('namespace%s*$') then                    -- namespace ClassName
        return true
    end

    -- Array callable patterns with class names
    if context_before:match('%[%s*$') and                            -- [ClassName, 'method']
       context_after:match('^%s*,%s*[\'"]') then
        return true
    end

    -- Exception handling patterns
    if context_before:match('catch%s*%(%s*$') or                     -- catch(ClassName
       context_before:match('throw%s+new%s*$') then                  -- throw new ClassName
        return true
    end

    -- Trait usage patterns
    if context_before:match('use%s*$') and
       not context_before:match('^%s*use%s*$') then                  -- use TraitName; (inside class)
        return true
    end

    return false
end

-- Helper function to remove string literals and comments for safer parsing
function M.remove_string_literals_and_comments(line)
    local result = line

    -- Remove single-line comments
    result = result:gsub('//.*$', '')
    result = result:gsub('#.*$', '')

    -- Remove multi-line comments (basic - doesn't handle multi-line)
    result = result:gsub('/%*.*%*/', '')

    -- Remove string literals (basic - doesn't handle escaped quotes)
    result = result:gsub('"[^"]*"', '""')  -- Double quotes
    result = result:gsub("'[^']*'", "''")  -- Single quotes

    -- Remove heredoc/nowdoc (basic)
    result = result:gsub('<<<[^>]*>>>', '""')

    return result
end

-- Enhanced validation for variable occurrences
function M.is_valid_variable_occurrence(line, col, variable_name, before_char, after_char)
    -- Must be word-bounded
    if (before_char ~= '' and before_char:match('[%w_]')) or
       (after_char ~= '' and after_char:match('[%w_]')) then
        return false
    end

    -- Additional context checks
    local context_before = col > 10 and line:sub(col - 10, col - 1) or line:sub(1, col - 1)
    local context_after = line:sub(col + #variable_name, col + #variable_name + 10)

    -- Skip if it's part of a different variable (e.g., $variable vs $variables)
    if before_char == '$' or after_char:match('^[%w_]') then
        return false
    end

    -- Skip if it's in a class name or constant context
    if context_before:match('class%s*$') or context_before:match('const%s*$') then
        return false
    end

    -- Skip if it's in a function name context
    if context_before:match('function%s*$') then
        return false
    end

    return true
end

-- Find actual position in original line after string/comment removal
function M.find_actual_position_in_original_line(original_line, cleaned_line, cleaned_pos)
    -- Simple mapping - for complex cases, we'd need more sophisticated tracking
    local original_pos = cleaned_pos

    -- This is a simplified version - in practice, you'd need to track
    -- exactly where each character was removed from
    return original_pos
end

return M