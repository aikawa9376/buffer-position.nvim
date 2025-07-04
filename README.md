# phprefactoring.nvim

A comprehensive PHP refactoring plugin for Neovim that brings PHPStorm-like refactoring capabilities to your favorite editor.

## Important

This plugin is still in development, please report any issues you find.

## ✨ Features

This plugin provides essential PHP refactoring operations:

### 🔄 Core Refactoring Operations

- **Extract Variable** - Extract expressions into variables
- **Extract Method** - Extract code blocks into methods
- **Extract Class** - Extract functionality into new classes
- **Extract Interface** - Generate interfaces from classes
- **Introduce Constant** - Extract values into class constants
- **Introduce Field** - Extract values into class properties
- **Introduce Parameter** - Extract values into function parameters
- **Change Signature** - Modify function/method signatures safely
- **Pull Members Up** - Move members to parent classes

### 🧠 Smart Analysis

- **TreeSitter Support** - Uses TreeSitter for context detection with regex fallback
- **Context Awareness** - Commands adapt based on cursor position and selection
- **Single File Focus** - Reliable refactoring within individual PHP files

## 📋 Requirements

- **Neovim 0.5+** (for LSP support)
- **[nui.nvim](https://github.com/MunifTanjim/nui.nvim)** - For beautiful UI components
- **Optional**: TreeSitter PHP parser (`TSInstall php`)
- **Optional**: PHP LSP server (Intelephense, PHPActor)

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'adibhanna/phprefactoring.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  ft = 'php',
  config = function()
    require('phprefactoring').setup({
      -- Configuration options
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'adibhanna/phprefactoring.nvim',
  requires = {
    'MunifTanjim/nui.nvim',
  },
  ft = 'php',
  config = function()
    require('phprefactoring').setup()
  end,
}
```

## ⚙️ Configuration

```lua
require('phprefactoring').setup({
  -- UI Configuration
  ui = {
    use_floating_menu = true,    -- Use floating windows for dialogs
    border = 'rounded',          -- Border style: 'rounded', 'single', 'double'
    width = 40,                  -- Dialog width
    height = nil,                -- Auto-calculated height
    highlights = {
      menu_title = 'Title',
      menu_border = 'FloatBorder',
      menu_item = 'Normal',
      menu_selected = 'PmenuSel',
      menu_shortcut = 'Comment',
    }
  },

  -- Refactoring Options
  refactor = {
    auto_format = true,          -- Auto-format after refactoring
  },




})
```

## 🎯 Usage

### Commands

All refactoring operations are available as commands:

```vim
:PHPExtractVariable       " Extract selection to variable
:PHPExtractMethod         " Extract selection to method
:PHPExtractClass          " Extract selection to class
:PHPExtractInterface      " Extract interface from class
:PHPIntroduceConstant     " Introduce constant
:PHPIntroduceField        " Introduce field/property
:PHPIntroduceParameter    " Introduce parameter
:PHPChangeSignature       " Change method signature
:PHPPullMembersUp         " Pull members to parent class
```

### Custom Keymaps

You can create your own keymaps using the commands:

```lua
-- Example keymaps (add to your Neovim config)
vim.keymap.set('v', '<leader>rv', '<cmd>PHPExtractVariable<cr>', { desc = 'Extract variable' })
vim.keymap.set('v', '<leader>rm', '<cmd>PHPExtractMethod<cr>', { desc = 'Extract method' })
vim.keymap.set('v', '<leader>rc', '<cmd>PHPExtractClass<cr>', { desc = 'Extract class' })
vim.keymap.set('n', '<leader>ri', '<cmd>PHPExtractInterface<cr>', { desc = 'Extract interface' })
vim.keymap.set('n', '<leader>ic', '<cmd>PHPIntroduceConstant<cr>', { desc = 'Introduce constant' })
vim.keymap.set('n', '<leader>if', '<cmd>PHPIntroduceField<cr>', { desc = 'Introduce field' })
vim.keymap.set('n', '<leader>ip', '<cmd>PHPIntroduceParameter<cr>', { desc = 'Introduce parameter' })
vim.keymap.set('n', '<leader>cs', '<cmd>PHPChangeSignature<cr>', { desc = 'Change signature' })
vim.keymap.set('n', '<leader>pm', '<cmd>PHPPullMembersUp<cr>', { desc = 'Pull members up' })
```

**Note:** These keymaps will work in PHP files. You can customize them to your preference.

## 🧪 Examples

### Extract Variable

```php
// Before
$user = User::find($request->get('user_id'));

// Select `$request->get('user_id')` and run :PHPExtractVariable
// After
$userId = $request->get('user_id');
$user = User::find($userId);
```

### Extract Method

```php
// Before (select the validation code)
if (empty($name)) {
    throw new InvalidArgumentException('Name is required');
}
if (strlen($name) < 3) {
    throw new InvalidArgumentException('Name too short');
}

// After running :PHPExtractMethod
private function validateName($name)
{
    if (empty($name)) {
        throw new InvalidArgumentException('Name is required');
    }
    if (strlen($name) < 3) {
        throw new InvalidArgumentException('Name too short');
    }
}

// Original location becomes:
$this->validateName($name);
```

### Introduce Constant

```php
// Before (cursor on the string)
if ($user->role === 'administrator') {

// After running :PHPIntroduceConstant
const ROLE_ADMINISTRATOR = 'administrator';

if ($user->role === self::ROLE_ADMINISTRATOR) {
```

### Extract Interface

```php
// Before (cursor in class)
class UserService
{
    public function createUser($data) { /* ... */ }
    public function updateUser($id, $data) { /* ... */ }
    public function deleteUser($id) { /* ... */ }
    private function validateData($data) { /* ... */ }
}

// After running :PHPExtractInterface
interface UserServiceInterface
{
    public function createUser($data);
    public function updateUser($id, $data);
    public function deleteUser($id);
}

class UserService implements UserServiceInterface
{
    // ... implementation
}
```

### Change Signature

```php
// Before (cursor on method signature)
public function processUser($userId, $data) { /* ... */ }

// After running :PHPChangeSignature
// Enter new signature: processUser($userId, $data, $options = [])
public function processUser($userId, $data, $options = []) { /* ... */ }
```

## 🏗️ Architecture

### Parser Integration

The plugin automatically detects and uses the best available parsing method:

1. **TreeSitter Auto-Detection** - Automatically uses TreeSitter if PHP parser is available
2. **Regex Fallback** - Falls back to regex patterns when TreeSitter is unavailable

### UI Components

Built on [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for:

- **Input dialogs** for collecting user input
- **Confirmation dialogs** for destructive operations
- **Notification system** for user feedback

## 🚀 Getting Started

1. **Install the plugin** using your preferred package manager
2. **Install dependencies**: `nui.nvim`
3. **Optional**: Install TreeSitter PHP parser: `:TSInstall php` (auto-detected for better context detection)
4. **Use commands directly** or create custom keymaps
5. **Start refactoring** in your PHP files!

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### Development Setup

1. Clone the repository
2. Install dependencies: `nui.nvim`
3. Set up TreeSitter PHP parser: `:TSInstall php` (auto-detected for context detection)

### Adding New Refactoring Operations

1. Create a new module in `lua/phprefactoring/refactors/`
2. Add the command to `plugin/phprefactoring.lua`
3. Add the function to `lua/phprefactoring/init.lua`
4. Update documentation

## 📝 License

MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- Inspired by JetBrains PHPStorm's excellent refactoring tools
- Built on the amazing [nui.nvim](https://github.com/MunifTanjim/nui.nvim) library
