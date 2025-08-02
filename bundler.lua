---@class Bundler
local Bundler = {
    _cwd = '',
    _libname = '',
    _separator = '/',
    _prefixsymb = '_G.',
    _out = {},
    _entryfile = {},
    _libnamestack = {},
    _reg = {
        emptyline = '^%s*$',
        space = '^%s*(.-)%s*$',
        spacecomment = '^%s*--%s*.*',
        require = {
            noparenthesis = "require%s*%s*['\"]([^'\"]+)['\"]",
            parenthesis = "require%s*%s*%(['\"]([^'\"]+)['\"]%)"
        },
    }
}

function Bundler:bundle(pwd, entrypoint, out)
    self:_initialize(pwd, entrypoint, out)

    local collected_paths = {}
    local files_queue = { self._entryfile }

    self._out:write('_G.__LOADED = {}\n')

    while #files_queue > 0 do
        local data = table.remove(files_queue, #files_queue)

        print('Processing: ' .. data.ospath)

        local expect_comment_close = false
        local mod_name = self:_path_to_name(data.path)

        self:_write_mod_header(mod_name)

        for rawline in data.file:lines() do
            local continue = true

            -- All processing must use trimmed
            local line = rawline:match(self._reg.space)

            if continue and expect_comment_close then
                local pos = line:find(']]')
                if pos and pos == 1 or line:sub(pos - 1, pos - 1) ~= '\\' then
                    expect_comment_close = false
                end
                continue = false
            end

            if continue then
                local iscomment = self:_starts_with(line, '--')
                local isempty = line:match(self._reg.emptyline) ~= nil

                if iscomment or isempty then
                    if self:_starts_with(line, '--[[') then
                        expect_comment_close = true
                    end
                    continue = false
                end

                if continue then
                    -- Check for require statements
                    local path = line:match(self._reg.require.noparenthesis) or
                        line:match(self._reg.require.parenthesis)

                    if path then
                        local ospath = self:_path_fixer(path)

                        if not collected_paths[path] then
                            collected_paths[path] = true

                            if self:_file_exists(ospath) then
                                local file = io.open(ospath)

                                if not file then
                                    error('Could not find file "' .. ospath .. '"')
                                end

                                table.insert(files_queue, {
                                    path = path,
                                    file = file,
                                    ospath = ospath,
                                })
                            end
                        end

                        if self:_file_exists(ospath) then
                            local name = self:_path_to_name(path)
                            line = (line
                                :gsub("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)", name)
                                :gsub("require%s+['\"]([^'\"]+)['\"]", name)
                                :gsub("require%s+([%w_%.]+)", name)) .. '()'
                        end
                    end

                    self._out:write(line .. '\n')
                end
            end
        end

        data.file:close()
        self:_write_mod_footer(mod_name)
    end

    self._out:write('return ' ..
        self._prefixsymb .. 'main()\n')
    self._out:close()
end

function Bundler:_initialize(pwd, entrypoint, out)
    self._cwd = pwd

    if self:_is_windows() then
        self._separator = '\\'
    end

    if self:_file_exists(out) then
        local temp = io.open(out, 'w') --[[ @as file* ]]
        temp:write('')
        temp:close()
    else
        self:_create_missing_dirs(out)
    end

    self._out = io.open(out, 'a') --[[ @as file* ]]

    local file = io.open(pwd .. self._separator .. entrypoint, 'r')

    if not file then
        error('Could not find file "' .. pwd .. self._separator .. entrypoint .. '"')
    end

    self._entryfile = {
        path = 'main',
        file = io.open(pwd .. self._separator .. entrypoint, 'r'),
        ospath = pwd .. '/' .. entrypoint
    }
end

function Bundler:_is_windows()
    if package.config:sub(1, 1) == '\\' then
        return true
    end
    return false
end

function Bundler:_file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function Bundler:_starts_with(string, prefix)
    return string.sub(string, 1, #prefix) == prefix
end

function Bundler:_path_fixer(lua_path)
    local result = lua_path:gsub('%.', self._separator)
    local final = ''
    for _, v in pairs({ self._cwd, result .. '.lua' }) do
        final = (final .. v .. self._separator):gsub('\n', '')
    end
    return final:gsub(self._separator .. "$", "")
end

function Bundler:_path_to_name(path)
    return self._prefixsymb .. path:gsub("[%.%/]", "") .. self._libname
end

function Bundler:_write_mod_header(mod_name)
    self._out:write(
        'function ' .. mod_name .. '()\n' ..
        'if _G.__LOADED[' .. mod_name .. '] and _G.__LOADED[' .. mod_name .. '].called then\n' ..
        'return _G.__LOADED[' .. mod_name .. '].M\n' ..
        'end\n' ..
        '_G.__LOADED[' .. mod_name .. '] = {called = true,M = (function()\n'
    -- mod content goes here
    )
end

function Bundler:_write_mod_footer(mod_name)
    self._out:write(
        'end)()\n' ..
        '}\n' ..
        'return _G.__LOADED[' .. mod_name .. '].M\n' ..
        'end\n'
    )
end

function Bundler:_create_missing_dirs(path)
    path = path:gsub(self._cwd, '')

    local dir

    if self:_is_windows() then
        dir = path:match("(.*\\)")
    else
        dir = path:match("(.*/)")
    end

    if dir then
        local current_dir = ''
        for part in dir:gmatch("[^" .. self._separator .. "]+") do
            current_dir = current_dir .. part .. self._separator
            if not self:_file_exists(current_dir) then
                os.execute("mkdir " .. current_dir)
            end
        end
    end
end

return Bundler

--
---@class Bundler
---@field private _out file*
---@field private _reg Regex
---@field private _cwd string
---@field private _entryfile file*
---@field private _separator string
---@field private _prefixsymb string
---@field bundle fun(self: Bundler, pwd: string, entrypoint: string, out: string): nil
---@field private _is_windows fun(self: Bundler): boolean
---@field private _path_to_name fun(self: Bundler, path: string): string
---@field private _path_fixer fun(self: Bundler, lua_path: string): string
---@field private _create_missing_dirs fun(self: Bundler, path: string): nil
---@field private _write_mod_footer fun(self: Bundler, mod_name: string): nil
---@field private _write_mod_header fun(self: Bundler, mod_name: string): nil
---@field private _file_exists fun(self: Bundler, path: string): boolean | nil
---@field private _starts_with fun(self: Bundler, str: string, prefix: string): boolean
---@field private _initialize fun(self: Bundler, pwd: string, entrypoint: string, out: string): nil
--
---@class Regex
---@field space string
---@field emptyline string
---@field spacecomment string
---@field require { noparenthesis: string, parenthesis: string }
