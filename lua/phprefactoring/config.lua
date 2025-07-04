-- Configuration for phprefactoring.nvim

local M = {}

-- Default configuration options
M.defaults = {
    -- UI options
    ui = {
        -- Use floating window for UI dialogs
        use_floating_menu = true,
        -- Menu border style
        border = 'rounded',
        -- Menu width
        width = 40,
        -- Menu height (auto-calculated if nil)
        height = nil,
        -- Highlight groups
        highlights = {
            menu_title = 'Title',
            menu_border = 'FloatBorder',
            menu_item = 'Normal',
            menu_selected = 'PmenuSel',
            menu_shortcut = 'Comment',
        }
    },

    -- Refactoring options
    refactor = {
        -- Auto-format after refactoring
        auto_format = true,
    },




}

-- Current options (will be merged with user config)
M.options = {}

-- Setup function to merge user config with defaults
function M.setup(user_config)
    M.options = vim.tbl_deep_extend('force', M.defaults, user_config or {})
    return M.options
end

-- Get current configuration
function M.get()
    return M.options
end

-- Update specific option
function M.set(key, value)
    local keys = vim.split(key, '.', { plain = true })
    local current = M.options

    for i = 1, #keys - 1 do
        if not current[keys[i]] then
            current[keys[i]] = {}
        end
        current = current[keys[i]]
    end

    current[keys[#keys]] = value
end

return M
