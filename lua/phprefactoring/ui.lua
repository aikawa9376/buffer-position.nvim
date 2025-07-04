-- UI module using nui.nvim for phprefactoring
-- Provides floating menus and input dialogs for refactoring operations

local Menu = require('nui.menu')
local Input = require('nui.input')
local Popup = require('nui.popup')
local event = require('nui.utils.autocmd').event
local config = require('phprefactoring.config')

local M = {}



-- Show input dialog for getting user input
function M.show_input(opts, on_submit)
    local conf = config.get()

    opts = opts or {}
    local title = opts.title or 'Input'
    local prompt = opts.prompt or '> '
    local default_value = opts.default or ''
    local placeholder = opts.placeholder or ''

    local input = Input({
        position = '50%',
        size = {
            width = opts.width or 40,
            height = 1,
        },
        border = {
            style = conf.ui.border,
            text = {
                top = '[' .. title .. ']',
                top_align = 'center',
            },
        },
        win_options = {
            winhighlight = string.format(
                'Normal:%s,FloatBorder:%s',
                conf.ui.highlights.menu_item,
                conf.ui.highlights.menu_border
            ),
        },
    }, {
        prompt = prompt,
        default_value = default_value,
        on_close = function()
            -- Input closed without submission
        end,
        on_submit = function(value)
            if on_submit then
                on_submit(value)
            end
        end,
    })

    input:mount()

    -- Auto-close on buffer leave
    input:on(event.BufLeave, function()
        input:unmount()
    end)

    return input
end

-- Show confirmation dialog
function M.show_confirm(message, on_confirm)
    local conf = config.get()

    local menu_items = {
        Menu.item('Yes'),
        Menu.item('No'),
    }

    local menu = Menu({
        position = '50%',
        size = {
            width = math.max(#message + 4, 20),
            height = 5,
        },
        border = {
            style = conf.ui.border,
            text = {
                top = '[Confirm]',
                top_align = 'center',
            },
        },
        win_options = {
            winhighlight = string.format(
                'Normal:%s,FloatBorder:%s',
                conf.ui.highlights.menu_item,
                conf.ui.highlights.menu_border
            ),
        },
    }, {
        lines = menu_items,
        keymap = {
            focus_next = { 'j', '<Down>', '<Tab>' },
            focus_prev = { 'k', '<Up>', '<S-Tab>' },
            close = { '<Esc>', '<C-c>', 'q' },
            submit = { '<CR>', '<Space>' },
        },
        on_close = function()
            on_confirm(false)
        end,
        on_submit = function(item)
            on_confirm(item.text == 'Yes')
        end,
    })

    -- Set the message content
    menu:mount()
    vim.api.nvim_buf_set_lines(menu.bufnr, 0, 0, false, { '', '  ' .. message, '' })

    -- Auto-close on buffer leave
    menu:on(event.BufLeave, function()
        menu:unmount()
    end)

    return menu
end

-- Show preview window with before/after comparison
function M.show_preview(title, before_content, after_content, on_confirm)
    local conf = config.get()

    local popup = Popup({
        position = '50%',
        size = {
            width = '80%',
            height = '70%',
        },
        border = {
            style = conf.ui.border,
            text = {
                top = '[' .. title .. ' Preview]',
                top_align = 'center',
                bottom = 'Press <CR> to apply, <Esc> to cancel',
                bottom_align = 'center',
            },
        },
        win_options = {
            winhighlight = string.format(
                'Normal:%s,FloatBorder:%s',
                conf.ui.highlights.menu_item,
                conf.ui.highlights.menu_border
            ),
        },
    })

    popup:mount()

    -- Split the window vertically to show before/after
    local lines = {}
    local max_lines = math.max(#before_content, #after_content)

    -- Header
    table.insert(lines, '  BEFORE' .. string.rep(' ', 35) .. '│  AFTER')
    table.insert(lines, string.rep('─', 40) .. '┼' .. string.rep('─', 40))

    -- Content comparison
    for i = 1, max_lines do
        local before_line = before_content[i] or ''
        local after_line = after_content[i] or ''

        -- Truncate lines if too long
        if #before_line > 38 then
            before_line = before_line:sub(1, 35) .. '...'
        end
        if #after_line > 38 then
            after_line = after_line:sub(1, 35) .. '...'
        end

        -- Pad to fixed width
        before_line = before_line .. string.rep(' ', 38 - #before_line)
        after_line = after_line .. string.rep(' ', 38 - #after_line)

        table.insert(lines, '  ' .. before_line .. '│  ' .. after_line)
    end

    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)

    -- Set up keymaps
    popup:map('n', '<CR>', function()
        popup:unmount()
        if on_confirm then
            on_confirm(true)
        end
    end, { noremap = true })

    popup:map('n', '<Esc>', function()
        popup:unmount()
        if on_confirm then
            on_confirm(false)
        end
    end, { noremap = true })

    popup:map('n', 'q', function()
        popup:unmount()
        if on_confirm then
            on_confirm(false)
        end
    end, { noremap = true })

    -- Auto-close on buffer leave
    popup:on(event.BufLeave, function()
        popup:unmount()
        if on_confirm then
            on_confirm(false)
        end
    end)

    return popup
end

-- Show notification message
function M.show_notification(message, level)
    level = level or 'info'

    -- Use vim.notify if available, otherwise fall back to echo
    if vim.notify then
        local log_level = vim.log.levels.INFO
        if level == 'error' then
            log_level = vim.log.levels.ERROR
        elseif level == 'warn' then
            log_level = vim.log.levels.WARN
        end

        vim.notify(message, log_level, { title = 'PHP Refactoring' })
    else
        local hl = 'Normal'
        if level == 'error' then
            hl = 'ErrorMsg'
        elseif level == 'warn' then
            hl = 'WarningMsg'
        end

        vim.api.nvim_echo({ { '[PHP Refactoring] ' .. message, hl } }, true, {})
    end
end

return M
