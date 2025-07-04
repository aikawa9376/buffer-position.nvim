-- Plugin entry point for phprefactoring.nvim
-- This file is loaded automatically by Neovim when the plugin is installed

if vim.g.loaded_phprefactoring then
    return
end
vim.g.loaded_phprefactoring = 1

-- Only load for PHP files or when explicitly requested
local function should_load()
    local ft = vim.bo.filetype
    return ft == 'php' or vim.g.phprefactoring_force_load
end

-- Create commands immediately but defer actual plugin loading
local function create_commands()
    local commands = {
        'PHPExtractVariable',
        'PHPExtractMethod',
        'PHPExtractClass',
        'PHPExtractInterface',
        'PHPIntroduceConstant',
        'PHPIntroduceField',
        'PHPIntroduceParameter',
        'PHPChangeSignature',
        'PHPPullMembersUp'
    }

    -- Command mapping to actual method names
    local command_map = {
        PHPExtractVariable = 'extract_variable',
        PHPExtractMethod = 'extract_method',
        PHPExtractClass = 'extract_class',
        PHPExtractInterface = 'extract_interface',
        PHPIntroduceConstant = 'introduce_constant',
        PHPIntroduceField = 'introduce_field',
        PHPIntroduceParameter = 'introduce_parameter',
        PHPChangeSignature = 'change_signature',
        PHPPullMembersUp = 'pull_members_up'
    }

    for _, cmd in ipairs(commands) do
        vim.api.nvim_create_user_command(cmd, function(opts)
            -- Lazy load the actual plugin when first command is used
            local method_name = command_map[cmd]
            if method_name then
                require('phprefactoring')[method_name](opts)
            else
                vim.notify('Unknown command: ' .. cmd, vim.log.levels.ERROR)
            end
        end, {
            desc = 'PHP Refactoring: ' .. cmd:sub(4),
            range = true,
            nargs = '*'
        })
    end
end

-- Autocommand to load plugin for PHP files
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'php',
    callback = function()
        if not vim.g.phprefactoring_loaded then
            create_commands()
            vim.g.phprefactoring_loaded = true
        end
    end,
    group = vim.api.nvim_create_augroup('PHPRefactoring', { clear = true })
})

-- If we're already in a PHP file, create commands immediately
if should_load() then
    create_commands()
    vim.g.phprefactoring_loaded = true
end
