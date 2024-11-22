---@class Bundler
local Bundler = {
    _now = os.time(),
    _cwd = '',
    _config = {},
    _separator = '/',
    _prefixsymb = '_G.',
    _postfixsymb = '__',
    _cmt_cmd_prefix = '--!',
    _out = {},
    _entryfile = {},
    _cmds = {
        skip = 'skip',
        endskip = 'endskip'
    },
    _reg = {
        emptyline = '^%s*$',
        spacecomment = '^%s*--%s*.*',
        space = '^%s*(.-)%s*$',
        require = {
            noparenthesis = "require%s*%s*['\"]([^'\"]+)['\"]",
            parenthesis = "require%s*%s*%(['\"]([^'\"]+)['\"]%)"
        },
    }
}

function Bundler:bundle(pwd, entrypoint, out, config)
    self:_initialize(pwd, entrypoint, out, config)

    local skip = 0
    local collected_paths = {}
    local files_queue = { self._entryfile }

    self:_write_cmt_cmd(self._cmds.skip)
    self._out:write('_G.__LOADED = {}\n')
    self:_write_cmt_cmd(self._cmds.endskip)

    while #files_queue > 0 do
        local data = table.remove(files_queue, #files_queue)

        print('Processing: ' .. data.ospath)

        local expect_comment_close = false
        local mod_name = self:_concat_suffix(self:_path_to_name(self._config.libname or data.path))

        self:_write_mod_header(mod_name)

        for rawline in data.file:lines() do
            -- All processing must use trimmed
            local line = rawline:match(self._reg.space)

            if self:_starts_with(line, '--!') then
                if self:_match_cmt_cmd(self._cmds.skip, line) then
                    skip = skip + 1
                    goto continue
                end

                if self:_match_cmt_cmd(self._cmds.endskip, line) then
                    skip = skip - 1
                    goto continue
                end
            end

            if skip ~= 0 then
                goto continue
            end

            if expect_comment_close then
                local pos = line:find(']]')
                if pos then
                    if pos == 1 or line:sub(pos - 1, pos - 1) ~= '\\' then
                        expect_comment_close = false
                    end
                end
                goto continue
            end

            local iscomment = self:_starts_with(line, '--')
            local isempty = line:match(self._reg.emptyline) ~= nil

            if iscomment or isempty then
                if self:_starts_with(line, '--[[') then
                    expect_comment_close = true
                end
                goto continue
            end

            -- Check for require statements
            local path = line:match(self._reg.require.noparenthesis) or line:match(self._reg.require.parenthesis)
            if path then
                local ospath = self:_path_fixer(path)

                if not collected_paths[path] then
                    collected_paths[path] = true
                    if self:_file_exists(ospath) then
                        table.insert(files_queue, {
                            path = path,
                            file = io.open(ospath),
                            ospath = ospath,
                        })
                    end
                end

                if self:_file_exists(ospath) then
                    local name = self:_concat_suffix(self:_path_to_name(path))
                    line = (line
                        :gsub("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)", name)
                        :gsub("require%s+['\"]([^'\"]+)['\"]", name)
                        :gsub("require%s+([%w_%.]+)", name)) .. '()'
                end
            end

            self._out:write(line .. '\n')
            ::continue::
        end

        skip = 0
        data.file:close()
        self:_write_mod_footer(mod_name)
    end

    self:_write_cmt_cmd(self._cmds.skip)
    local mainfn_name = 'main__'

    if self._config.libname then
        mainfn_name = self._config.libname .. '__'
    end

    self._out:write('return ' ..
        self._prefixsymb .. self:_concat_suffix(mainfn_name) .. '()\n')
    self:_write_cmt_cmd(self._cmds.endskip)
    self._out:close()
end

function Bundler:_initialize(pwd, entrypoint, out, config)
    self._cwd = pwd
    self._config = config or {}
    if self:_is_windows() then
        self._separator = '\\'
    end
    self._out = io.open(out, 'a') --[[ @as file* ]]
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
    return self._prefixsymb .. path:gsub("[%.%/]", "") .. self._postfixsymb
end

function Bundler:_write_mod_header(mod_name)
    self:_write_cmt_cmd(self._cmds.skip)
    self._out:write(
        'function ' .. mod_name .. '()\n' ..
        'if _G.__LOADED[' .. mod_name .. '] and _G.__LOADED[' .. mod_name .. '].called then\n' ..
        'return _G.__LOADED[' .. mod_name .. '].M\n' ..
        'end\n' ..
        '_G.__LOADED[' .. mod_name .. '] = {called = true,M = (function()\n'
    -- mod content goes here
    )
    self:_write_cmt_cmd(self._cmds.endskip)
end

function Bundler:_write_mod_footer(mod_name)
    self:_write_cmt_cmd(self._cmds.skip)
    self._out:write(
        'end)()\n' ..
        '}\n' ..
        'return _G.__LOADED[' .. mod_name .. '].M\n' ..
        'end\n'
    )
    self:_write_cmt_cmd(self._cmds.endskip)
end

function Bundler:_write_cmt_cmd(cmd)
    self._out:write(self:_get_cmt_cmd(cmd))
end

function Bundler:_match_cmt_cmd(cmd, line)
    return line == self:_get_cmt_cmd(cmd, true)
end

function Bundler:_get_cmt_cmd(cmtcmd, nnl)
    local cmd = self._cmt_cmd_prefix .. ' ' .. cmtcmd
    if nnl then
        return cmd
    end
    return cmd .. '\n'
end

function Bundler:_concat_suffix(mod_name)
    return mod_name .. self._now .. self._postfixsymb .. 'bt'
end

return Bundler

--
-- Types
--
---@class Bundler
---@field _now integer
---@field _cwd string
---@field _config? Config
---@field _separator string
---@field _prefixsymb string
---@field _postfixsymb string
---@field _cmt_cmd_prefix string
---@field _out file*
---@field _entryfile file*
---@field _cmds CommentCmd
---@field _reg Regex
---@field bundle fun(self: Bundler, pwd: string, entrypoint: string, out: string, config?: Config): nil
---@field _initialize fun(self: Bundler, pwd: string, entrypoint: string, out: string, config: Config): nil
---@field _get_cmt_cmd fun(self: Bundler, cmtcmd: string, nnl?: boolean): string
---@field _match_cmt_cmd fun(self: Bundler, cmd: string, line: string): boolean
---@field _write_cmt_cmd fun(self: Bundler, cmd: string): nil
---@field _write_mod_header fun(self: Bundler, mod_name: string): nil
---@field _write_mod_footer fun(self: Bundler, mod_name: string): nil
---@field _path_to_name fun(self: Bundler, path: string): string
---@field _path_fixer fun(self: Bundler, lua_path: string): string
---@field _starts_with fun(self: Bundler, str: string, prefix: string): boolean
---@field _file_exists fun(self: Bundler, path: string): boolean | nil
---@field _is_windows fun(self: Bundler): boolean
---@field _concat_suffix fun(self: Bundler, mod_name: string): string
---
---@class CommentCmd
---@field skip string
---@field endskip string
---
---@class Regex
---@field emptyline string
---@field spacecomment string
---@field space string
---@field require { noparenthesis: string, parenthesis: string }
---
---@class Config
---@field libname? string
--@field env? table -- TO DO
