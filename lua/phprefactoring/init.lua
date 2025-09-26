-- Main phprefactoring module
-- This is the entry point for all refactoring operations

local config = require('phprefactoring.config')
local ui = require('phprefactoring.ui')
local parser = require('phprefactoring.parser')

local M = {}

-- Initialize the plugin with user configuration
function M.setup(user_config)
    config.setup(user_config)

    -- Initialize parser
    parser.setup()
end

-- Individual refactoring methods
function M.change_signature()
    local signature = require('phprefactoring.refactors.signature')
    signature.execute()
end

function M.introduce_variable()
    local introduce = require('phprefactoring.refactors.introduce')
    introduce.variable()
end

function M.extract_variable()
    -- Alias for introduce_variable for backward compatibility
    M.introduce_variable()
end

function M.introduce_constant()
    local introduce = require('phprefactoring.refactors.introduce')
    introduce.constant()
end

function M.introduce_field()
    local introduce = require('phprefactoring.refactors.introduce')
    introduce.field()
end

function M.introduce_parameter()
    local introduce = require('phprefactoring.refactors.introduce')
    introduce.parameter()
end

function M.extract_method()
    local extract = require('phprefactoring.refactors.extract')
    extract.method()
end

function M.extract_class()
    local extract = require('phprefactoring.refactors.extract')
    extract.class()
end

function M.extract_interface()
    local extract = require('phprefactoring.refactors.extract')
    extract.interface()
end

function M.pull_members_up()
    local members = require('phprefactoring.refactors.members')
    members.pull_up()
end

function M.rename_variable()
    local rename = require('phprefactoring.refactors.rename')
    rename.variable()
end

function M.rename_method()
    local rename = require('phprefactoring.refactors.rename')
    rename.method()
end

function M.rename_class()
    local rename = require('phprefactoring.refactors.rename')
    rename.class()
end

return M
