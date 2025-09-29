# buffer-position.nvim

A lightweight Neovim plugin that displays a scrollbar-like indicator for your current position in the buffer.

<!-- Add a screenshot here -->
<!-- ![demo](demo.png) -->

## Features

-   Minimalist, scrollbar-like indicator in a floating window.
-   Appears after a configurable delay of cursor inactivity.
-   Highly customizable:
    -   Position (left/right), width, and margins.
    -   Window height (percentage of screen).
    -   Characters and highlights for active and inactive states.
    -   Line spacing for a sparser look.
-   Disappears automatically on cursor movement.

## Installation

Install with your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "aikawa9376/buffer-position.nvim",
    config = function()
        require("buffer-position").setup({
            -- your custom config
        })
    end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "aikawa9376/buffer-position.nvim",
    config = function()
        require("buffer-position").setup()
    end,
}
```

## Configuration

The plugin comes with the following default configuration. You can override any of these values in the `setup()` function.

```lua
{
    position = "right", -- "left" or "right"
    width = 2,
    offset = { x = -1, y = 0 },
    height_percentage = 0.8,
    active_char = "──",
    inactive_char = " ─",
    transparent = true,
    line_spacing = 1, -- number of blank lines between characters
    show_delay = 1000,
    hide_delay = 1000, -- ms
    auto_hide = false,
    highlights = {
        active = { fg = "#ffffff" },
        inactive = { fg = "#505050" },
    },
}
```

### Options

-   `position` (`"left"` or `"right"`): Position of the indicator on the screen.
-   `width` (`number`): Width of the floating window.
-   `offset` (`table`): Fine-tune the window position with `x` and `y` offsets.
-   `height_percentage` (`number`): Height of the window as a percentage of screen height (0.0 to 1.0).
-   `active_char` (`string`): Character to display for the current position.
-   `inactive_char` (`string`): Character to display for the rest of the track.
-   `transparent` (`boolean`): Whether the window background should be transparent.
-   `line_spacing` (`number`): Number of blank lines to insert between indicator characters.
-   `show_delay` (`number`): Delay in milliseconds after `CursorHold` before showing the indicator.
-   `auto_hide` (`boolean`): If `true`, automatically hides the indicator after `hide_delay`. If `false`, it only hides on `CursorMoved`.
-   `hide_delay` (`number`): Delay in milliseconds before hiding the indicator (only if `auto_hide` is `true`).
-   `highlights` (`table`): Configure the highlight groups for `active` and `inactive` states. You can set `fg`, `bg`, `bold`, `italic`, or `link` to an existing highlight group.

## Acknowledgements

This plugin is heavily inspired by [ahkohd/buffer-sticks.nvim](https://github.com/ahkohd/buffer-sticks.nvim).

## License

This plugin is licensed under the [MIT License](./LICENSE).
