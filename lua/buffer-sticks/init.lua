-- luacheck: globals vim

---@class BufferSticks
---@field setup function Setup the buffer sticks plugin
local M = {}

---@class BufferSticksState
---@field win number Window handle for the floating window
---@field buf number Buffer handle for the display buffer
---@field visible boolean Whether the buffer sticks are currently visible
---@field timer number|nil Timer ID for hiding the window
local state = {
	win = -1,
	buf = -1,
	visible = false,
	timer = nil,
}

---@class BufferSticksHighlights
---@field fg? string Foreground color (hex color or highlight group name)
---@field bg? string Background color (hex color or highlight group name)
---@field bold? boolean Bold text
---@field italic? boolean Italic text
---@field link? string Link to existing highlight group (alternative to defining colors)

---@class BufferSticksOffset
---@field x number Horizontal offset from default position
---@field y number Vertical offset from default position

---@class BufferSticksPadding
---@field vertical number Vertical padding for the window

---@class BufferSticksConfig
---@field position "left"|"right" Position of the buffer sticks on screen
---@field width number Width of the floating window
---@field offset BufferSticksOffset Position offset for fine-tuning
---@field padding BufferSticksPadding Padding for the window
---@field active_char string Character to display for the cursor position
---@field inactive_char string Character to display for the track
---@field transparent boolean Whether the background should be transparent
---@field line_spacing number Number of blank lines between characters
---@field winblend? number Window blend/transparency level (0-100, overrides transparent)
---@field hide_delay number Delay in milliseconds before hiding the indicator
---@field highlights table<string, BufferSticksHighlights> Highlight groups for active/inactive states
local config = {
	position = "right", -- "left" or "right"
	width = 2,
	offset = { x = 0, y = 0 },
	padding = { vertical = 1 },
	active_char = "──",
	inactive_char = " ─",
	transparent = true,
	line_spacing = 1, -- number of blank lines between characters
	hide_delay = 1000, -- ms
	highlights = {
		active = { fg = "#ffffff" },
		inactive = { fg = "#505050" },
	},
}

---@class WindowInfo
---@field buf number Buffer handle
---@field win number Window handle

---Create and configure the floating window for buffer sticks
---@return WindowInfo window_info Information about the created window and buffer
local function create_floating_window()
	local v_padding = (config.padding and config.padding.vertical) or 0
	local height = vim.o.lines - (v_padding * 2)
	local width = config.width

	-- Position based on config
	local col = config.position == "right" and vim.o.columns - width + config.offset.x or 0 + config.offset.x
	local row = v_padding + config.offset.y

	-- Create buffer if needed
	if not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].bufhidden = "wipe"
		vim.bo[state.buf].filetype = "buffersticks"
	end

	-- Create window
	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 10,
	}

	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_config(state.win, win_config)
	else
		state.win = vim.api.nvim_open_win(state.buf, false, win_config)
	end

	-- Set transparency using winblend after window creation
	if config.winblend then
		vim.api.nvim_win_set_option(state.win, "winblend", config.winblend)
	elseif config.transparent then
		vim.api.nvim_win_set_option(state.win, "winblend", 100)
	else
		vim.api.nvim_win_set_option(state.win, "winblend", 0)
	end

	-- Set window background based on transparency
	if not config.winblend and not config.transparent then
		vim.api.nvim_win_set_option(state.win, "winhl", "Normal:BufferSticksBackground")
	else
		vim.api.nvim_win_set_option(state.win, "winhl", "Normal:NONE")
	end

	return { buf = state.buf, win = state.win }
end

---Render cursor position indicator in the floating window
local function render_position()
	if not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local total_lines = vim.api.nvim_buf_line_count(0)
	if total_lines <= 1 then
		return
	end

	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local win_height = vim.api.nvim_win_get_height(state.win)
	local line_spacing = config.line_spacing or 0
	local effective_height = math.floor(win_height / (1 + line_spacing))

	if effective_height <= 0 then
		return
	end

	local percentage = (current_line - 1) / (total_lines - 1)
	local thumb_pos = math.floor(percentage * (effective_height - 1))

	local lines = {}
	for i = 1, effective_height do
		if i - 1 == thumb_pos then
			table.insert(lines, config.active_char)
		else
			table.insert(lines, config.inactive_char)
		end
		for _ = 1, line_spacing do
			table.insert(lines, "")
		end
	end

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

	-- Set highlights
	vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
	for i = 1, effective_height do
		local hl_group = (i - 1 == thumb_pos) and "BufferSticksActive" or "BufferSticksInactive"
		local line_index = (i - 1) * (1 + line_spacing)
		vim.api.nvim_buf_add_highlight(state.buf, -1, hl_group, line_index, 0, -1)
	end
end

local function hide()
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
		state.win = -1
	end
	if state.timer then
		vim.fn.timer_stop(state.timer)
		state.timer = nil
	end
	state.visible = false
end

---Show the buffer sticks floating window
local function show()
	-- Don't show for non-buflisted buffers or tiny buffers
	if not vim.bo.buflisted or vim.api.nvim_buf_line_count(0) <= 1 then
		return
	end

	create_floating_window()
	render_position()
	state.visible = true

	-- Stop any existing timer
	if state.timer then
		vim.fn.timer_stop(state.timer)
	end

	-- Start a new timer to hide the window
	state.timer = vim.fn.timer_start(config.hide_delay, function()
		vim.schedule(hide)
	end)
end

---Setup the buffer sticks plugin with user configuration
---@param opts? BufferSticksConfig User configuration options to override defaults
function M.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", config, opts)

	-- Helper function to set up highlights
	local function setup_highlights()
		local is_transparent = config.winblend or config.transparent

		if config.highlights.active.link then
			vim.api.nvim_set_hl(0, "BufferSticksActive", { link = config.highlights.active.link })
		else
			local active_hl = vim.deepcopy(config.highlights.active)
			if is_transparent then
				active_hl.bg = nil -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksActive", active_hl)
		end

		if config.highlights.inactive.link then
			vim.api.nvim_set_hl(0, "BufferSticksInactive", { link = config.highlights.inactive.link })
		else
			local inactive_hl = vim.deepcopy(config.highlights.inactive)
			if is_transparent then
				inactive_hl.bg = nil -- Remove background for transparency
			end
			vim.api.nvim_set_hl(0, "BufferSticksInactive", inactive_hl)
		end

		if not is_transparent then
			vim.api.nvim_set_hl(0, "BufferSticksBackground", { bg = "#1e1e1e" })
		end
	end

	setup_highlights()

	local augroup = vim.api.nvim_create_augroup("BufferSticks", { clear = true })

	-- Show on cursor hold
	vim.api.nvim_create_autocmd({ "CursorHold" }, {
		group = augroup,
		pattern = "*",
		callback = function()
			vim.schedule(show)
		end,
	})

	-- Hide on cursor move
	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		group = augroup,
		pattern = "*",
		callback = function()
			if state.visible then
				vim.schedule(hide)
			end
		end,
	})

	-- Reapply highlights when colorscheme changes
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			vim.schedule(setup_highlights)
		end,
	})

	-- Reposition window when terminal is resized
	vim.api.nvim_create_autocmd("VimResized", {
		group = augroup,
		callback = function()
			if state.visible then
				vim.schedule(function()
					hide()
					show()
				end)
			end
		end,
	})
end

return M