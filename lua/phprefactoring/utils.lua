-- Utility functions for phprefactoring.nvim

local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}



-- Format PHP code using available formatter
function M.format_code()
    local conf = config.get()

    -- Try LSP formatting first
    if vim.lsp.buf.format then
        vim.lsp.buf.format({ async = false })
        ui.show_notification('Code formatted using LSP', 'info')
        return
    end

    -- Fallback to external formatters
    local formatters = { 'php-cs-fixer', 'phpcbf', 'prettier' }

    for _, formatter in ipairs(formatters) do
        if vim.fn.executable(formatter) == 1 then
            M.format_with_external(formatter)
            return
        end
    end

    ui.show_notification('No PHP formatter available', 'warn')
end

-- Format using external formatter
function M.format_with_external(formatter)
    local file = vim.api.nvim_buf_get_name(0)
    if file == '' then
        ui.show_notification('No file to format', 'warn')
        return
    end

    local cmd = ''
    if formatter == 'php-cs-fixer' then
        cmd = 'php-cs-fixer fix "' .. file .. '"'
    elseif formatter == 'phpcbf' then
        cmd = 'phpcbf "' .. file .. '"'
    elseif formatter == 'prettier' then
        cmd = 'prettier --write "' .. file .. '"'
    end

    if cmd ~= '' then
        local result = vim.fn.system(cmd)
        if vim.v.shell_error == 0 then
            vim.cmd('edit!') -- Reload the file
            ui.show_notification('Code formatted with ' .. formatter, 'info')
        else
            ui.show_notification('Formatting failed: ' .. result, 'error')
        end
    end
end

-- Get PHP class name from file path
function M.get_class_name_from_file(file_path)
    local base_name = vim.fn.fnamemodify(file_path, ':t:r')
    return base_name
end

-- Get namespace from file path (PSR-4 convention)
function M.get_namespace_from_file(file_path)
    local dir_path = vim.fn.fnamemodify(file_path, ':h')
    local cwd = vim.fn.getcwd()

    -- Simple heuristic: assume src/ directory
    local relative_path = dir_path:gsub(cwd, ''):gsub('^/', '')

    if relative_path:match('^src/') then
        local namespace = relative_path:gsub('^src/', ''):gsub('/', '\\')
        return namespace ~= '' and namespace or nil
    end

    return nil
end

-- Create new PHP class file
function M.create_class_file(class_name, file_path)
    local namespace = M.get_namespace_from_file(file_path)

    local lines = {
        '<?php',
        ''
    }

    if namespace then
        table.insert(lines, 'namespace ' .. namespace .. ';')
        table.insert(lines, '')
    end

    table.insert(lines, 'class ' .. class_name)
    table.insert(lines, '{')
    table.insert(lines, '    // Implementation')
    table.insert(lines, '}')

    -- Write file
    vim.fn.writefile(lines, file_path)

    return file_path
end

-- Create new PHP interface file
function M.create_interface_file(interface_name, file_path, methods)
    local namespace = M.get_namespace_from_file(file_path)

    local lines = {
        '<?php',
        ''
    }

    if namespace then
        table.insert(lines, 'namespace ' .. namespace .. ';')
        table.insert(lines, '')
    end

    table.insert(lines, 'interface ' .. interface_name)
    table.insert(lines, '{')

    -- Add method signatures
    if methods then
        for _, method in ipairs(methods) do
            local params = method.parameters and table.concat(method.parameters, ', ') or ''
            table.insert(lines, string.format('    public function %s(%s);', method.name, params))
        end
    else
        table.insert(lines, '    // Method signatures will be added here')
    end

    table.insert(lines, '}')

    -- Write file
    vim.fn.writefile(lines, file_path)

    return file_path
end

-- Validate PHP syntax
function M.validate_syntax()
    local file = vim.api.nvim_buf_get_name(0)
    if file == '' then
        ui.show_notification('No file to validate', 'warn')
        return
    end

    local result = vim.fn.system('php -l "' .. file .. '"')

    if vim.v.shell_error == 0 then
        ui.show_notification('PHP syntax is valid', 'info')
    else
        ui.show_notification('PHP syntax error: ' .. result, 'error')
    end
end

-- Get current PHP version
function M.get_php_version()
    local result = vim.fn.system('php --version')
    if vim.v.shell_error == 0 then
        local version = result:match('PHP (%d+%.%d+%.%d+)')
        return version
    end
    return nil
end

-- Check if we're in a PHP project
function M.is_php_project()
    local indicators = {
        'composer.json',
        'composer.lock',
        'artisan',       -- Laravel
        'wp-config.php', -- WordPress
        'index.php'
    }

    for _, indicator in ipairs(indicators) do
        if vim.fn.filereadable(indicator) == 1 then
            return true
        end
    end

    return false
end

-- Find project root
function M.find_project_root()
    local current_dir = vim.fn.expand('%:p:h')

    while current_dir ~= '/' do
        if vim.fn.filereadable(current_dir .. '/composer.json') == 1 then
            return current_dir
        end
        current_dir = vim.fn.fnamemodify(current_dir, ':h')
    end

    return vim.fn.getcwd()
end

-- Generate PSR-4 compliant file path
function M.generate_psr4_path(class_name, namespace)
    local project_root = M.find_project_root()
    local src_dir = project_root .. '/src'

    local path = src_dir
    if namespace then
        local namespace_path = namespace:gsub('\\', '/')
        path = path .. '/' .. namespace_path
    end

    -- Ensure directory exists
    vim.fn.mkdir(path, 'p')

    return path .. '/' .. class_name .. '.php'
end

-- Clean up imports in PHP file
function M.clean_imports()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local use_statements = {}
    local used_classes = {}
    local cleaned_lines = {}

    -- Find all use statements
    for i, line in ipairs(lines) do
        local use_class = line:match('^use%s+([^;]+);')
        if use_class then
            table.insert(use_statements, { line = i, class = use_class, original = line })
        else
            table.insert(cleaned_lines, line)
        end
    end

    -- Find used classes in the code
    local code_content = table.concat(cleaned_lines, '\n')
    for _, use_stmt in ipairs(use_statements) do
        local class_name = use_stmt.class:match('([^\\]+)$') -- Get last part of namespace
        if code_content:match(class_name) then
            table.insert(used_classes, use_stmt)
        end
    end

    -- Rebuild file with only used imports
    local final_lines = {}
    local in_use_section = false

    for _, line in ipairs(lines) do
        if line:match('^use%s+') then
            if not in_use_section then
                -- Add all used imports here
                for _, used in ipairs(used_classes) do
                    table.insert(final_lines, used.original)
                end
                in_use_section = true
            end
            -- Skip original use statement
        else
            table.insert(final_lines, line)
            if line:match('%S') then -- Non-empty line
                in_use_section = false
            end
        end
    end

    -- Update buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, final_lines)

    local removed = #use_statements - #used_classes
    if removed > 0 then
        ui.show_notification(string.format('Removed %d unused imports', removed), 'info')
    else
        ui.show_notification('No unused imports found', 'info')
    end
end

return M
