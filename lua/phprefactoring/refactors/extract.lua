-- Extract refactoring module
-- Handles method and class extraction

local parser = require('phprefactoring.parser')
local ui = require('phprefactoring.ui')
local config = require('phprefactoring.config')

local M = {}

-- Extract method from selected code
function M.method()
    local selection, start_pos, end_pos = parser.get_visual_selection()

    if not selection or #selection == 0 then
        ui.show_notification('Please select code to extract into a method', 'warn')
        return
    end

    local code_block = table.concat(selection, '\n')

    -- Analyze the selected code to determine parameters and return values
    local analysis = M.analyze_code_block(code_block, start_pos, end_pos)

    ui.show_input({
        title = 'Extract Method',
        prompt = 'Method name: ',
        default = M.generate_method_name(code_block),
        width = 40
    }, function(method_name)
        if method_name and method_name ~= '' then
            M.perform_extract_method(code_block, method_name, analysis, start_pos, end_pos)
        end
    end)
end

-- Extract class from selected code
function M.class()
    local selection, start_pos, end_pos = parser.get_visual_selection()

    if not selection or #selection == 0 then
        ui.show_notification('Please select code to extract into a class', 'warn')
        return
    end

    if not parser.is_in_class() then
        ui.show_notification('Must be inside a class to extract to new class', 'warn')
        return
    end

    local code_block = table.concat(selection, '\n')

    ui.show_input({
        title = 'Extract Class',
        prompt = 'Class name: ',
        default = M.generate_class_name(code_block),
        width = 40
    }, function(class_name)
        if class_name and class_name ~= '' then
            M.perform_extract_class(code_block, class_name, start_pos, end_pos)
        end
    end)
end

-- Extract interface from class
function M.interface()
    if not parser.is_in_class() then
        ui.show_notification('Must be inside a class to extract interface', 'warn')
        return
    end

    -- Get current class info
    local class_info = M.get_current_class_info()
    if not class_info then
        ui.show_notification('Could not analyze current class', 'error')
        return
    end

    ui.show_input({
        title = 'Extract Interface',
        prompt = 'Interface name: ',
        default = class_info.name .. 'Interface',
        width = 40
    }, function(interface_name)
        if interface_name and interface_name ~= '' then
            M.perform_extract_interface(interface_name, class_info)
        end
    end)
end

-- Perform method extraction
function M.perform_extract_method(code_block, method_name, analysis, start_pos, end_pos)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Generate method signature
    local params = {}
    for _, param in ipairs(analysis.parameters) do
        if param.type == 'mixed' then
            table.insert(params, '$' .. param.name)
        else
            table.insert(params, param.type .. ' $' .. param.name)
        end
    end

    local method_signature = string.format('private function %s(%s)', method_name, table.concat(params, ', '))
    local return_statement = analysis.returns and ('return $' .. analysis.returns .. ';') or ''

    -- Build the complete method
    local method_lines = {
        '    ' .. method_signature,
        '    {',
    }

    -- Add the code block with proper indentation
    for line in code_block:gmatch('[^\n]+') do
        table.insert(method_lines, '        ' .. line)
    end

    if return_statement ~= '' then
        table.insert(method_lines, '        ' .. return_statement)
    end

    table.insert(method_lines, '    }')
    table.insert(method_lines, '')

    -- Generate method call
    local call_params = {}
    for _, param in ipairs(analysis.parameters) do
        table.insert(call_params, '$' .. param.name)
    end

    local method_call
    if analysis.returns then
        method_call = string.format('$%s = $this->%s(%s);', analysis.returns, method_name,
            table.concat(call_params, ', '))
    else
        method_call = string.format('$this->%s(%s);', method_name, table.concat(call_params, ', '))
    end

    -- Apply the refactoring immediately
    M.apply_extract_method(method_lines, method_call, start_pos, end_pos)
end

-- Apply method extraction changes
function M.apply_extract_method(method_lines, method_call, start_pos, end_pos)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Find where to insert the method
    local insert_pos = M.find_method_insert_position()

    -- Insert the new method
    vim.api.nvim_buf_set_lines(bufnr, insert_pos, insert_pos, false, method_lines)

    -- Replace selected code with method call
    if start_pos and end_pos then
        -- Calculate adjusted positions after method insertion
        local adjusted_start = start_pos[1]
        local adjusted_end = end_pos[1]

        if start_pos[1] >= insert_pos then
            adjusted_start = adjusted_start + #method_lines
            adjusted_end = adjusted_end + #method_lines
        end

        -- Get proper indentation
        local indent = M.get_indentation_at_line(adjusted_start)

        -- Replace the selection with method call
        vim.api.nvim_buf_set_lines(bufnr, adjusted_start, adjusted_end + 1, false, { indent .. method_call })
    end

    -- Auto-format if enabled
    local conf = config.get()
    if conf.refactor.auto_format then
        vim.lsp.buf.format({ async = false })
    end
end

-- Analyze code block to determine parameters and return values
function M.analyze_code_block(code_block, start_pos, end_pos)
    local analysis = {
        parameters = {},
        returns = nil,
        used_variables = {},
        defined_variables = {}
    }

    -- Find ALL variables used in the code block (more comprehensive patterns)
    local variable_patterns = {
        '%$([%w_]+)',   -- Basic variable usage: $var
        '%$([%w_]+)%[', -- Array access: $var[key]
        '%$([%w_]+)->', -- Object property: $var->prop
        '%$([%w_]+)::', -- Static access: $var::method
    }

    for _, pattern in ipairs(variable_patterns) do
        for var in code_block:gmatch(pattern) do
            -- Skip 'this' as it's always available in class methods
            if var ~= 'this' then
                analysis.used_variables[var] = true
            end
        end
    end

    -- Find variables defined within the code block (more comprehensive)
    local definition_patterns = {
        -- Assignment patterns
        '%$([%w_]+)%s*=',                                            -- Basic assignment: $var =
        'foreach%s*%([^%)]*%s+as%s+%$([%w_]+)%s*%)',                 -- foreach value: foreach($x as $var)
        'foreach%s*%([^%)]*%s+as%s+%$[%w_]+%s*=>%s*%$([%w_]+)%s*%)', -- foreach key-value: as $key => $var
        'for%s*%(%s*%$([%w_]+)%s*=',                                 -- for loop: for($var = ...)
        'while%s*%(%s*%$([%w_]+)%s*=',                               -- while with assignment
        'if%s*%(%s*%$([%w_]+)%s*=',                                  -- if with assignment
        'catch%s*%([^%)]*%s+%$([%w_]+)%s*%)',                        -- catch block: catch(Exception $var)
    }

    for _, pattern in ipairs(definition_patterns) do
        for var in code_block:gmatch(pattern) do
            analysis.defined_variables[var] = true
        end
    end

    -- Get the current function's existing parameters to exclude them
    local current_function_params = M.get_current_function_parameters()

    -- Variables that are used but not defined are potential parameters
    for var, _ in pairs(analysis.used_variables) do
        if not analysis.defined_variables[var] then
            -- Add as parameter if it's used but not defined in the extracted code
            -- This includes existing function parameters that need to be passed to the extracted method
            local param_type = M.infer_parameter_type(var, code_block)
            table.insert(analysis.parameters, { name = var, type = param_type })
        end
    end

    -- Better return value detection
    analysis.returns = M.detect_return_value(code_block, analysis)

    return analysis
end

-- Infer parameter type based on variable usage in code
function M.infer_parameter_type(var_name, code_block)
    local var_pattern = '%$' .. var_name

    -- Check for specific usage patterns to infer type
    if code_block:match(var_pattern .. '%[') then
        return 'array'  -- Used as array
    elseif code_block:match(var_pattern .. '->') then
        return 'object' -- Used as object
    elseif code_block:match('strlen%s*%(%s*' .. var_pattern) or
        code_block:match('trim%s*%(%s*' .. var_pattern) or
        code_block:match('strtolower%s*%(%s*' .. var_pattern) then
        return 'string' -- Used in string functions
    elseif code_block:match(var_pattern .. '%s*[<>=!]') or
        code_block:match('[<>=!]%s*' .. var_pattern) then
        -- Used in comparisons, could be int or string
        if code_block:match('%d+%s*[<>=!]%s*' .. var_pattern) or
            code_block:match(var_pattern .. '%s*[<>=!]%s*%d+') then
            return 'int'
        else
            return 'string'
        end
    else
        return 'mixed' -- Default fallback
    end
end

-- Detect return value from code block
function M.detect_return_value(code_block, analysis)
    local lines = {}
    for line in code_block:gmatch('[^\n]+') do
        table.insert(lines, vim.trim(line))
    end

    -- Check if there's an explicit return statement
    for _, line in ipairs(lines) do
        local return_match = line:match('return%s+%$([%w_]+)')
        if return_match then
            return return_match
        end
    end

    -- Check if the last line defines a variable that could be returned
    if #lines > 0 then
        local last_line = lines[#lines]
        local assigned_var = last_line:match('%$([%w_]+)%s*=')
        if assigned_var and analysis.defined_variables[assigned_var] then
            -- Only consider it a return value if it's used after being defined
            local var_used_after = false
            for i = #lines, 1, -1 do
                if lines[i]:match('%$' .. assigned_var .. '[^=]') then -- Used but not assigned
                    var_used_after = true
                    break
                end
                if lines[i]:match('%$' .. assigned_var .. '%s*=') then -- Found the assignment
                    break
                end
            end

            if not var_used_after then
                return assigned_var
            end
        end
    end

    return nil
end

-- Get parameters of the current function to avoid including them as new parameters
function M.get_current_function_parameters()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor_pos[1] - 1

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, current_line + 20, false)
    local current_params = {}

    -- Look backwards to find the function declaration
    for i = current_line, math.max(0, current_line - 30), -1 do
        if lines[i + 1] then
            local line = lines[i + 1]

            -- Different function declaration patterns
            local function_patterns = {
                'function%s+[%w_]*%s*%(([^%)]*%))',             -- function name(params)
                'public%s+function%s+[%w_]*%s*%(([^%)]*%))',    -- public function name(params)
                'private%s+function%s+[%w_]*%s*%(([^%)]*%))',   -- private function name(params)
                'protected%s+function%s+[%w_]*%s*%(([^%)]*%))', -- protected function name(params)
                'static%s+function%s+[%w_]*%s*%(([^%)]*%))',    -- static function name(params)
            }

            for _, pattern in ipairs(function_patterns) do
                local params_string = line:match(pattern)
                if params_string then
                    -- Extract parameter names from function signature
                    -- Handle parameters with type hints: Type $param, $param = default, etc.
                    for param in params_string:gmatch('%$([%w_]+)') do
                        current_params[param] = true
                    end
                    return current_params
                end
            end

            -- Also check for multiline function declarations
            if line:match('function%s+[%w_]*%s*%(') and not line:match('%)') then
                -- Start of multiline function declaration
                local full_declaration = line
                for j = i + 2, math.min(i + 10, #lines) do
                    if lines[j] then
                        full_declaration = full_declaration .. ' ' .. vim.trim(lines[j])
                        if lines[j]:match('%)') then
                            break
                        end
                    end
                end

                -- Extract parameters from full declaration
                for param in full_declaration:gmatch('%$([%w_]+)') do
                    current_params[param] = true
                end
                return current_params
            end
        end
    end

    return current_params
end

-- Get current class information (using regex fallback for stability)
function M.get_current_class_info()
    return M.get_current_class_info_fallback()
end

-- Fallback function for when treesitter is not available (cursor-aware)
function M.get_current_class_info_fallback()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- Get cursor position (0-indexed)

    local class_info = {
        name = nil,
        methods = {},
        properties = {},
        start_line = nil,
        end_line = nil
    }

    -- Find all classes in the file first
    local classes = {}
    for i, line in ipairs(lines) do
        local class_name = line:match('^%s*class%s+(%w+)')
        if class_name then
            table.insert(classes, {
                name = class_name,
                start_line = i - 1,
                end_line = nil
            })
        end
    end

    -- Find the end of each class
    for _, class in ipairs(classes) do
        local brace_count = 0
        local found_opening_brace = false

        for i = class.start_line + 1, #lines do
            local line = lines[i]
            for char in line:gmatch('.') do
                if char == '{' then
                    brace_count = brace_count + 1
                    found_opening_brace = true
                elseif char == '}' then
                    brace_count = brace_count - 1
                    if brace_count == 0 and found_opening_brace then
                        class.end_line = i - 1
                        break
                    end
                end
            end
            if class.end_line then break end
        end
    end

    -- Find which class the cursor is in
    local current_class = nil
    for _, class in ipairs(classes) do
        if cursor_line >= class.start_line and (class.end_line == nil or cursor_line <= class.end_line) then
            current_class = class
            break
        end
    end

    if not current_class then
        return nil
    end

    -- Build class info for the current class only
    class_info.name = current_class.name
    class_info.start_line = current_class.start_line
    class_info.end_line = current_class.end_line

    -- Find methods and properties only within the current class
    local start_line = current_class.start_line
    local end_line = current_class.end_line or #lines

    for i = start_line + 1, end_line do
        local line = lines[i]

        -- Find public methods
        local method_name = line:match('^%s*public%s+function%s+(%w+)')
        if method_name then
            table.insert(class_info.methods, {
                name = method_name,
                line = i - 1,
                visibility = 'public'
            })
        end

        -- Find public properties
        local prop_name = line:match('^%s*public%s+%$(%w+)')
        if prop_name then
            table.insert(class_info.properties, {
                name = prop_name,
                line = i - 1,
                visibility = 'public'
            })
        end
    end

    return class_info.name and class_info or nil
end

-- Helper functions for name generation
function M.generate_method_name(code_block)
    -- Simple heuristics for method names
    if code_block:match('validate') or code_block:match('check') then
        return 'validate'
    elseif code_block:match('calculate') or code_block:match('compute') then
        return 'calculate'
    elseif code_block:match('format') or code_block:match('convert') then
        return 'format'
    elseif code_block:match('process') or code_block:match('handle') then
        return 'process'
    else
        return 'extractedMethod'
    end
end

function M.generate_class_name(code_block)
    -- Simple heuristics for class names
    if code_block:match('validate') then
        return 'Validator'
    elseif code_block:match('format') or code_block:match('render') then
        return 'Formatter'
    elseif code_block:match('calculate') then
        return 'Calculator'
    elseif code_block:match('handle') or code_block:match('process') then
        return 'Handler'
    else
        return 'ExtractedClass'
    end
end

-- Helper functions for positioning
function M.find_method_insert_position()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find the end of the current class
    for i = #lines, 1, -1 do
        local line = lines[i]
        if line:match('^%s*}%s*$') then
            return i - 1 -- Insert before the closing brace
        end
    end

    return #lines
end

function M.get_indentation_at_line(line_num)
    local lines = vim.api.nvim_buf_get_lines(0, line_num, line_num + 1, false)
    if #lines > 0 then
        return lines[1]:match('^%s*') or ''
    end
    return ''
end

-- Find the end line of the current method
function M.find_method_end_line(start_line, all_lines)
    local brace_count = 0
    local found_method_start = false

    -- Look backwards to find the method start
    for i = start_line, math.max(1, start_line - 50), -1 do
        local line = all_lines[i]
        if line and line:match('function%s+[%w_]+%s*%(') then
            found_method_start = true
            break
        end
    end

    if not found_method_start then
        return start_line + 10 -- fallback
    end

    -- Look forward to find the method end
    for i = start_line, math.min(#all_lines, start_line + 100) do
        local line = all_lines[i]
        if line then
            for char in line:gmatch('.') do
                if char == '{' then
                    brace_count = brace_count + 1
                elseif char == '}' then
                    brace_count = brace_count - 1
                    if brace_count == 0 then
                        return i - 1 -- Convert to 0-based index
                    end
                end
            end
        end
    end

    return start_line + 10 -- fallback
end

-- Perform class extraction
function M.perform_extract_class(code_block, class_name, start_pos, end_pos)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Get current file path to determine where to create the new class
    local current_file = vim.api.nvim_buf_get_name(bufnr)
    local current_dir = vim.fn.fnamemodify(current_file, ':p:h')
    local new_file_path = current_dir .. '/' .. class_name .. '.php'

    -- Analyze the code block to determine what should be extracted
    local class_analysis = M.analyze_code_for_class_extraction(code_block)

    -- Build the new class content
    local class_content = M.build_extracted_class(class_name, code_block, class_analysis)

    -- Create the new class file
    M.create_class_file(new_file_path, class_content)

    -- Replace the original code with instantiation and usage of the new class
    M.replace_with_class_usage(code_block, class_name, class_analysis, start_pos, end_pos)
end

-- Perform interface extraction
function M.perform_extract_interface(interface_name, class_info)
    local conf = config.get()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Get current file path to determine where to create the interface
    local current_file = vim.api.nvim_buf_get_name(bufnr)
    local current_dir = vim.fn.fnamemodify(current_file, ':p:h')
    local interface_file_path = current_dir .. '/' .. interface_name .. '.php'

    -- Build interface content from class info
    local interface_content = M.build_interface_content(interface_name, class_info)

    -- Create the interface file
    M.create_class_file(interface_file_path, interface_content)

    -- Update the original class to implement the interface
    M.add_interface_implementation(class_info, interface_name)
end

-- Analyze code block for class extraction
function M.analyze_code_for_class_extraction(code_block)
    local analysis = {
        properties = {},
        methods = {},
        dependencies = {},
        constructor_params = {},
        internal_variables = {}
    }

    -- Find properties that might need to be moved to the new class
    for prop in code_block:gmatch('%$this->([%w_]+)') do
        analysis.properties[prop] = true
    end

    -- Find variables that are DEFINED (assigned) within the extracted code
    local definition_patterns = {
        '%$([%w_]+)%s*=',                                            -- Basic assignment: $var =
        'foreach%s*%([^%)]*%s+as%s+%$([%w_]+)%s*%)',                 -- foreach value: foreach($x as $var)
        'foreach%s*%([^%)]*%s+as%s+%$[%w_]+%s*=>%s*%$([%w_]+)%s*%)', -- foreach key-value: as $key => $var
        'for%s*%(%s*%$([%w_]+)%s*=',                                 -- for loop: for($var = ...)
        'catch%s*%([^%)]*%s+%$([%w_]+)%s*%)',                        -- catch block: catch(Exception $var)
    }

    for _, pattern in ipairs(definition_patterns) do
        for var in code_block:gmatch(pattern) do
            analysis.internal_variables[var] = true
        end
    end

    -- Find ALL variables used in the extracted code
    local used_variables = {}

    -- Primary pattern: variables with $ prefix (covers most cases)
    for var in code_block:gmatch('%$([%w_]+)') do
        if var ~= 'this' then
            used_variables[var] = true
        end
    end

    -- Also check for method calls that indicate we need the original class instance
    local needs_original_instance = code_block:match('%$this%->[%w_]+%(')
    if needs_original_instance then
        analysis.needs_service_instance = true
    end

    -- Get current method parameters to include them as potential dependencies
    local current_method_params = M.get_current_function_parameters()

    -- Dependencies are variables that are USED but NOT DEFINED within the extracted code
    -- Also include method parameters that are used in the extracted code
    for var, _ in pairs(used_variables) do
        if not analysis.internal_variables[var] then
            analysis.dependencies[var] = true
        end
    end

    -- Ensure method parameters that are used in the code are included as dependencies
    for param, _ in pairs(current_method_params) do
        if used_variables[param] then
            analysis.dependencies[param] = true
        end
    end

    return analysis
end

-- Build extracted class content
function M.build_extracted_class(class_name, code_block, analysis)
    local lines = {}

    -- Add PHP opening tag and namespace
    table.insert(lines, '<?php')
    table.insert(lines, '')

    -- Extract namespace from current file
    local current_namespace = M.get_current_namespace()
    if current_namespace then
        table.insert(lines, 'namespace ' .. current_namespace .. ';')
        table.insert(lines, '')
    end

    -- Class declaration
    table.insert(lines, 'class ' .. class_name)
    table.insert(lines, '{')

    -- Add properties
    if analysis.needs_service_instance then
        table.insert(lines, '    private $service;')
    end

    for prop, _ in pairs(analysis.properties) do
        table.insert(lines, '    private $' .. prop .. ';')
    end

    -- Add properties for dependencies
    local all_deps = {}
    for dep, _ in pairs(analysis.dependencies) do
        table.insert(all_deps, dep)
    end
    table.sort(all_deps)

    for _, dep in ipairs(all_deps) do
        table.insert(lines, '    private $' .. dep .. ';')
    end

    if analysis.needs_service_instance or next(analysis.properties) or next(analysis.dependencies) then
        table.insert(lines, '')
    end

    -- Add constructor if needed
    if next(analysis.dependencies) or next(analysis.properties) or analysis.needs_service_instance then
        local constructor_params = {}

        -- Add service instance if needed
        if analysis.needs_service_instance then
            table.insert(constructor_params, '$service')
        end

        -- Add dependencies in consistent order
        local dep_list = {}
        for dep, _ in pairs(analysis.dependencies) do
            table.insert(dep_list, dep)
        end
        table.sort(dep_list)

        for _, dep in ipairs(dep_list) do
            table.insert(constructor_params, '$' .. dep)
        end

        table.insert(lines, '    public function __construct(' .. table.concat(constructor_params, ', ') .. ')')
        table.insert(lines, '    {')

        if analysis.needs_service_instance then
            table.insert(lines, '        $this->service = $service;')
        end

        -- Add dependency assignments in consistent order (reuse same dep_list)
        for _, dep in ipairs(dep_list) do
            table.insert(lines, '        $this->' .. dep .. ' = $' .. dep .. ';')
        end

        table.insert(lines, '    }')
        table.insert(lines, '')
    end

    -- Add main method with the extracted code
    table.insert(lines, '    public function execute()')
    table.insert(lines, '    {')

    -- Process extracted code lines
    local code_lines = {}
    for line in code_block:gmatch('[^\n]+') do
        local processed_line = line

        -- Replace $this-> with $this->service-> for method calls if we need the service instance
        if analysis.needs_service_instance then
            processed_line = processed_line:gsub('%$this%->', '$this->service->')
        end

        -- Replace dependencies with property access
        for dep, _ in pairs(analysis.dependencies) do
            processed_line = processed_line:gsub('%$' .. dep .. '([^%w_])', '$this->' .. dep .. '%1')
            processed_line = processed_line:gsub('%$' .. dep .. '$', '$this->' .. dep)
        end

        table.insert(code_lines, processed_line)
    end

    -- Add the extracted code with proper indentation
    for i, line in ipairs(code_lines) do
        table.insert(lines, '        ' .. line)
    end

    -- Check if we need to add a return statement
    local has_return = false
    local last_assignment_var = nil

    for _, line in ipairs(code_lines) do
        if line:match('return') then
            has_return = true
            break
        end
        local var = line:match('%$([%w_]+)%s*=')
        if var then
            last_assignment_var = var
        end
    end

    -- If no explicit return and there's a meaningful last assignment, return it
    if not has_return and last_assignment_var then
        table.insert(lines, '')
        table.insert(lines, '        return $' .. last_assignment_var .. ';')
    end

    table.insert(lines, '    }')
    table.insert(lines, '}')

    return table.concat(lines, '\n')
end

-- Build interface content
function M.build_interface_content(interface_name, class_info)
    local lines = {}

    -- Add PHP opening tag and namespace
    table.insert(lines, '<?php')
    table.insert(lines, '')

    -- Extract namespace from current file
    local current_namespace = M.get_current_namespace()
    if current_namespace then
        table.insert(lines, 'namespace ' .. current_namespace .. ';')
        table.insert(lines, '')
    end

    -- Interface declaration
    table.insert(lines, 'interface ' .. interface_name)
    table.insert(lines, '{')

    -- Add public method signatures
    for _, method in ipairs(class_info.methods) do
        if method.visibility == 'public' then
            -- Get method signature from the original class
            local method_signature = M.get_method_signature(method.line)
            if method_signature then
                table.insert(lines, '    ' .. method_signature .. ';')
            end
        end
    end

    table.insert(lines, '}')

    return table.concat(lines, '\n')
end

-- Get current namespace from file
function M.get_current_namespace()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 20, false)

    for _, line in ipairs(lines) do
        local namespace = line:match('^namespace%s+([^;]+);')
        if namespace then
            return namespace
        end
    end

    return nil
end

-- Get method signature for interface
function M.get_method_signature(line_num)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 3, false)

    for _, line in ipairs(lines) do
        local signature = line:match('%s*public%s+(function%s+[^{]+)')
        if signature then
            return signature
        end
    end

    return nil
end

-- Create class/interface file
function M.create_class_file(file_path, content)
    local file = io.open(file_path, 'w')
    if file then
        file:write(content)
        file:close()
    else
        ui.show_notification('Could not create file: ' .. file_path, 'error')
    end
end

-- Replace extracted code with class usage
function M.replace_with_class_usage(code_block, class_name, analysis, start_pos, end_pos)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Build the replacement code
    local replacement_lines = {}

    -- Create instance
    local constructor_args = {}

    -- Add service instance if needed
    if analysis.needs_service_instance then
        table.insert(constructor_args, '$this')
    end

    -- Add dependencies in a consistent order
    local sorted_deps = {}
    for dep, _ in pairs(analysis.dependencies) do
        table.insert(sorted_deps, dep)
    end
    table.sort(sorted_deps) -- Sort for consistent ordering

    for _, dep in ipairs(sorted_deps) do
        table.insert(constructor_args, '$' .. dep)
    end

    local instance_creation = '$' ..
        string.lower(class_name) .. ' = new ' .. class_name .. '(' .. table.concat(constructor_args, ', ') .. ');'
    table.insert(replacement_lines, instance_creation)

    -- Call the execute method
    local method_call = '$result = $' .. string.lower(class_name) .. '->execute();'
    table.insert(replacement_lines, method_call)
    table.insert(replacement_lines, 'return $result;')

    -- Replace the selected code and clean up unreachable code
    if start_pos and end_pos then
        local indent = M.get_indentation_at_line(start_pos[1])
        local final_lines = {}
        for _, line in ipairs(replacement_lines) do
            table.insert(final_lines, indent .. line)
        end

        -- Simply replace the selected lines with our new code
        vim.api.nvim_buf_set_lines(bufnr, start_pos[1], end_pos[1] + 1, false, final_lines)

        -- Note: Unreachable code detection disabled due to complexity
        -- Users should manually review and remove unreachable code if needed
    end
end

-- Add interface implementation to class (using regex for stability)
function M.add_interface_implementation(class_info, interface_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find the exact class declaration line for the target class
    for i, line in ipairs(lines) do
        -- Look for class declaration that starts the line (not in extends clause)
        local class_match = line:match('^%s*class%s+([%w_]+)')
        if class_match == class_info.name then
            local new_line

            -- Check if class already implements interfaces
            if line:match('implements') then
                -- Add to existing implements list
                new_line = line:gsub('(implements%s+[^{]+)', '%1, ' .. interface_name)
            elseif line:match('extends') then
                -- Class extends another class, add implements after extends
                new_line = line:gsub('(extends%s+[^%s{]+)', '%1 implements ' .. interface_name)
            else
                -- Simple class, just add implements
                if line:match('{%s*$') then
                    -- Line ends with opening brace
                    new_line = line:gsub('(%s*{%s*)$', ' implements ' .. interface_name .. '%1')
                else
                    -- Add before any trailing whitespace or newline
                    new_line = line:gsub('(%s*)$', ' implements ' .. interface_name .. '%1')
                end
            end

            vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
            break
        end
    end
end

return M
