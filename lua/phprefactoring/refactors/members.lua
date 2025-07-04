-- Members refactoring module
-- Handles pulling members up to parent class and pushing members down to child classes

local parser = require('phprefactoring.parser')
local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}

-- Pull members up to parent class
function M.pull_up()
    if not parser.is_in_class() then
        ui.show_notification('Must be inside a class', 'warn')
        return
    end

    if not parser.has_parent_class() then
        ui.show_notification('Class has no parent class', 'warn')
        return
    end

    -- Get current class info
    local class_info = M.get_current_class_info()
    if not class_info then
        ui.show_notification('Could not analyze current class', 'error')
        return
    end

    -- Find parent class
    local parent_class_name = M.get_parent_class_name()
    if not parent_class_name then
        ui.show_notification('Could not determine parent class name', 'error')
        return
    end

    -- Get cursor position to determine which method to pull up
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local method_to_pull = M.find_method_at_cursor(cursor_line)

    if not method_to_pull then
        ui.show_notification('Place cursor on a method to pull up', 'warn')
        return
    end

    -- Check if method already exists in parent class
    if M.method_exists_in_parent(method_to_pull.name, parent_class_name) then
        ui.show_notification('Method already exists in parent class', 'warn')
        return
    end

    -- Move the method to parent class
    M.move_method_to_parent(method_to_pull, parent_class_name)
end

-- Helper functions for pull members up

-- Get current class information
function M.get_current_class_info()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    for i, line in ipairs(lines) do
        local line_idx = i - 1
        local class_name = line:match('^%s*class%s+(%w+)')
        if class_name then
            -- Check if cursor is within this class
            local brace_count = 0
            local found_opening = false
            local class_end = nil

            for j = i, #lines do
                local check_line = lines[j]
                for char in check_line:gmatch('.') do
                    if char == '{' then
                        brace_count = brace_count + 1
                        found_opening = true
                    elseif char == '}' then
                        brace_count = brace_count - 1
                        if brace_count == 0 and found_opening then
                            class_end = j - 1
                            break
                        end
                    end
                end
                if class_end then break end
            end

            if class_end and cursor_line >= line_idx and cursor_line <= class_end then
                return {
                    name = class_name,
                    start_line = line_idx,
                    end_line = class_end
                }
            end
        end
    end
    return nil
end

-- Get parent class name from current class
function M.get_parent_class_name()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    for i, line in ipairs(lines) do
        local line_idx = i - 1
        if line:match('^%s*class%s+') then
            -- Check if cursor is within this class
            local brace_count = 0
            local found_opening = false
            local class_end = nil

            for j = i, #lines do
                local check_line = lines[j]
                for char in check_line:gmatch('.') do
                    if char == '{' then
                        brace_count = brace_count + 1
                        found_opening = true
                    elseif char == '}' then
                        brace_count = brace_count - 1
                        if brace_count == 0 and found_opening then
                            class_end = j - 1
                            break
                        end
                    end
                end
                if class_end then break end
            end

            if class_end and cursor_line >= line_idx and cursor_line <= class_end then
                -- Extract parent class name
                local parent_name = line:match('extends%s+(%w+)')
                return parent_name
            end
        end
    end
    return nil
end

-- Find method at cursor position
function M.find_method_at_cursor(cursor_line)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Look backwards from cursor to find method start
    for i = cursor_line + 1, 1, -1 do
        local line = lines[i]
        if line then
            local method_name = line:match('^%s*public%s+function%s+(%w+)')
            if method_name then
                -- Find method end
                local brace_count = 0
                local method_end = nil

                for j = i, #lines do
                    local check_line = lines[j]
                    for char in check_line:gmatch('.') do
                        if char == '{' then
                            brace_count = brace_count + 1
                        elseif char == '}' then
                            brace_count = brace_count - 1
                            if brace_count == 0 then
                                method_end = j - 1
                                break
                            end
                        end
                    end
                    if method_end then break end
                end

                if method_end and cursor_line >= (i - 1) and cursor_line <= method_end then
                    return {
                        name = method_name,
                        start_line = i - 1,
                        end_line = method_end,
                        content = table.concat(vim.list_slice(lines, i, method_end + 1), '\n')
                    }
                end
            end
        end
    end
    return nil
end

-- Check if method exists in parent class
function M.method_exists_in_parent(method_name, parent_class_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find parent class in the same file
    for i, line in ipairs(lines) do
        local class_name = line:match('^%s*class%s+(%w+)')
        if class_name == parent_class_name then
            -- Look for the method within this class
            local brace_count = 0
            local found_opening = false
            local class_end = nil

            for j = i, #lines do
                local check_line = lines[j]
                for char in check_line:gmatch('.') do
                    if char == '{' then
                        brace_count = brace_count + 1
                        found_opening = true
                    elseif char == '}' then
                        brace_count = brace_count - 1
                        if brace_count == 0 and found_opening then
                            class_end = j - 1
                            break
                        end
                    end
                end
                if class_end then break end
            end

            -- Search for method within parent class
            for k = i, class_end or #lines do
                local check_line = lines[k]
                if check_line and check_line:match('function%s+' .. method_name .. '%s*%(') then
                    return true
                end
            end
            return false
        end
    end
    return false
end

-- Move method to parent class
function M.move_method_to_parent(method_info, parent_class_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find parent class
    local parent_insert_pos = nil
    for i, line in ipairs(lines) do
        local class_name = line:match('^%s*class%s+(%w+)')
        if class_name == parent_class_name then
            -- Find where to insert the method (before closing brace)
            local brace_count = 0
            local found_opening = false

            for j = i, #lines do
                local check_line = lines[j]
                for char in check_line:gmatch('.') do
                    if char == '{' then
                        brace_count = brace_count + 1
                        found_opening = true
                    elseif char == '}' then
                        brace_count = brace_count - 1
                        if brace_count == 0 and found_opening then
                            parent_insert_pos = j - 1
                            break
                        end
                    end
                end
                if parent_insert_pos then break end
            end
            break
        end
    end

    if not parent_insert_pos then
        ui.show_notification('Could not find parent class', 'error')
        return
    end

    -- Add method to parent class
    local method_lines = {}
    for line in method_info.content:gmatch('[^\n]+') do
        table.insert(method_lines, line)
    end
    table.insert(method_lines, '') -- Add blank line after method

    vim.api.nvim_buf_set_lines(bufnr, parent_insert_pos, parent_insert_pos, false, method_lines)

    -- Remove method from current class (adjust line numbers due to insertion)
    local lines_added = #method_lines
    local adjusted_start = method_info.start_line
    local adjusted_end = method_info.end_line + 1 -- Include the line after for removal

    if method_info.start_line > parent_insert_pos then
        adjusted_start = adjusted_start + lines_added
        adjusted_end = adjusted_end + lines_added
    end

    vim.api.nvim_buf_set_lines(bufnr, adjusted_start, adjusted_end, false, {})
end

return M
