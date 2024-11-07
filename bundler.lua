--#region Tokenizer
local letters_symbols = {}

-- ASCII values for A-Z
for i = 65, 90 do
    table.insert(letters_symbols, string.char(i))
end

-- ASCII values for a-z
for i = 97, 122 do
    table.insert(letters_symbols, string.char(i))
end

-- Common symbols
local common_symbols = { '!', '"', '#', '$', '%', '&', "'", '(', ')', '*', '+', ',', '-', '.', '/',
    ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '{', '|', '}', '~' }
for _, symbol in ipairs(common_symbols) do
    table.insert(letters_symbols, symbol)
end

local ttypes = {
    lparen = "lparen",
    string = "string",
    id = "id",
    any = nil
}

---@alias RequireTypes 'eager' | 'lazy'
---@alias Token { type: string, value: string }
---@alias ReqTypes { eager: string[], lazy: string[] }

---@class Tokenizer
---@field _path string
---@field _code string
---@field _file file*
---@field _cursor number
---@field _cchar string
---@field _tokens Token[]
---@field _expect_comment_close boolean
---@field _rawcode string
---@field _letters_symbols string[]
local Tokenizer = { code = '', cursor = 1, cchar = '', tokens = {} }
Tokenizer.__index = Tokenizer

---@param path string
---@return Tokenizer
function Tokenizer:new(path)
    local o = setmetatable({
        _path = path,
        _code = '',
        _cursor = 1,
        _cchar = '',
        _tokens = {},
        _expect_comment_close = false,
        _rawcode = '',
        _file = self:_get_file(path),
        _letters_symbols = letters_symbols,
    }, Tokenizer)
    o:_tokenize()
    return o
end

---@return Token[]
function Tokenizer:_tokenize()
    for v in self._file:lines() do
        self._code = v
        self._cursor = 1
        self._cchar = self._code:sub(1, 1)
        self._rawcode = self._rawcode .. '\n' .. v

        while self._cursor <= #self._code do
            if self._cursor > #self._code then break end

            if self:_is_comment() then
                break
            end

            if self:_is_alpha(self._cchar) then
                local id = self:_read_identifier()
                self:_push_token(ttypes.id, id)
            end

            if self._cchar == '"' or self._cchar == "'" then
                local str = self:_create_string(self._cchar)
                self:_push_token(ttypes.string, str)
            end

            if self:_includes_char(self.cchar) then
                self:_push_token(ttypes.any, self._cchar)
            end
            self:_next()
        end

        if not self._expect_comment_close and #self._tokens > 1 then
            self:_push_token(ttypes.any, '\n')
        end
    end

    return self._tokens
end

---@param path string
---@return file*
function Tokenizer:_get_file(path)
    local file = io.open(path, "r")
    if not file then
        error("\nCould not open file: " .. path)
    end
    return file
end

---@return string
function Tokenizer:to_str()
    return self._rawcode
end

function Tokenizer:close()
    self._file:close()
end

---@return ReqTypes
function Tokenizer:classify_requires()
    local eager = {}
    local lazy = {}
    local is_lazy = false
    local tokens = self._tokens

    for i = 1, #tokens do
        local token = tokens[i]

        if token.type then
            if token.value == "function" then
                is_lazy = true
            elseif token.value == "end" then
                is_lazy = false
            elseif token.value == "for" or token.value == "while" or token.value == "repeat" then
                is_lazy = true
            elseif token.value == "end" then
                is_lazy = false
            elseif token.value == "require" then
                local tkn = tokens[i + 1]
                local require_value = tkn.value

                if tkn.type == ttypes.lparen then
                    require_value = tokens[i + 2].value
                end

                if not is_lazy then
                    table.insert(eager, require_value)
                else
                    table.insert(lazy, require_value)
                end
            end
        end
    end

    return {
        eager = eager,
        lazy = lazy
    }
end

---@param delimiter string
---@return string
function Tokenizer:_create_string(delimiter)
    self:_next()
    local str = ''

    while self._cchar ~= delimiter do
        str = str .. self._cchar
        self:_next()
    end

    return str
end

---@param char string
---@return boolean
function Tokenizer:_is_alpha(char)
    local result = char:match("%a") ~= nil
    return result
end

---@param char string
---@return boolean
function Tokenizer:_is_number(char)
    local result = char:match("%d") ~= nil
    return result
end

---@return string
function Tokenizer:_next()
    if self._cursor > #self._code + 10 then
        error("\nCursor beyond the limit: " .. self._cursor .. ' -- ' .. #self._code)
    end
    self._cursor = self._cursor + 1
    self._cchar = self._code:sub(self._cursor, self._cursor)
    return self._cchar
end

---@return string
function Tokenizer:_read_identifier()
    local identifier = ''

    while self:_is_alpha(self._cchar) or self:_is_number(self._cchar) do
        identifier = identifier .. self._cchar
        self:_next()
    end

    return identifier
end

---@return string
function Tokenizer:_read_number()
    local allow_dot = true
    local number = ''

    while self:_is_number(self._code:sub(self._cursor, self._cursor)) or self._cchar ==
        '.' do
        if self._cchar == '.' and allow_dot then
            allow_dot = false
            number = number .. '.'
            self:_next()
        end
        number = number .. self._cchar
        self:_next()
    end
    return number
end

---@return boolean
function Tokenizer:_is_comment()
    while self._expect_comment_close and self._cursor <= #self._code do
        if self._cchar == ']' then
            self:_next() -- Skip the first ']'
            self:_next() -- Skip the second ']'
            self._expect_comment_close = false
            break
        end
        if self._expect_comment_close then
            self:_next()
        end
    end


    if self._expect_comment_close then
        return true
    end

    if self._cchar == '-' and self:_peek() == '-' then
        self:_next() -- Skip the first '-'
        self:_next() -- Skip the second '-'

        if self._cchar == '[' and self:_peek() == '[' then
            self._expect_comment_close = true
        end

        return true
    end

    return false
end

---@return string
function Tokenizer:_peek()
    local result = self._code:sub(self._cursor + 1, self._cursor + 1)
    return result
end

---@param type string
---@param value string
function Tokenizer:_push_token(type, value)
    table.insert(self._tokens, { type = type, value = value })
end

---@param char string
---@return boolean
function Tokenizer:_includes_char(char)
    for _, c in ipairs(self._letters_symbols) do
        if c == char then
            return true
        end
    end
    return false
end

--#endregion

--#region Bundler
local Bundler = {
    _cwd = '',
    _result_file_path = '',
    _collected_modules = {},
    _modules = {
        lazy = {},
        eager = {},
    },
    _bundle_header = [[
_G.__oreq__ = require
_G.__bundleregister__ = {
    eager = {},
    lazy = {},
}
function _G.__registerdepeager__(path, fn) __bundleregister__.eager[path] = fn() end
function _G.__registerdeplazy__(path, fn) __bundleregister__.lazy[path] = fn() end
require = function(path)
    if __bundleregister__.eager[path] then return __bundleregister__.eager[path] end
    if __bundleregister__.lazy[path] then return __bundleregister__.lazy[path]() end
    local dep = __oreq__(path)
    -- if dep then __bundleregister__[path] = dep end
    if dep then __bundleregister__.eager[path] = dep end
    return dep
end
]],
    _eager_module = [[
__registerdepeager__("{importpath}", function()
    {code}
end)
]],
    _lazy_module = [[
__registerdeplazy__("{importpath}", function()
    return function()
        {code}
    end
end)
]],
}

function Bundler:_init()
    self._cwd = self:_getcwd()
    self._result_file_path = self:_path_join({ self._cwd, 'bundle.lua' })
    local path = arg[1]
    local entrypoint = self:_path_join({ self._cwd, path })

    self:_bundle(entrypoint)

    local code = self._collected_modules[entrypoint]:to_str()
    self:_process_write('__entrypoint__', code, entrypoint, 'eager')
    self:_write_to_file(self._result_file_path, self._bundle_header)

    for _, v in pairs(self._collected_modules) do
        v:close()
    end

    print('\nDone. \nOutput path: ' .. self._result_file_path)
end

---@param path string
function Bundler:_bundle(path)
    if self:_file_exists(path) then
        local tokenizer = self:_get_tokenizer(path)
        local requires = tokenizer:classify_requires()

        ---@param reqpath string
        ---@param mode RequireTypes
        local function process_require(reqpath, mode)
            local file_os_path = self:_path_join({ self._cwd, self:_path_fixer(reqpath) .. '.lua' })
            if not self._collected_modules[file_os_path] then
                table.insert(self._modules[mode], file_os_path)
                self:_bundle(file_os_path)

                if self:_file_exists(file_os_path) then
                    local tkz = self:_get_tokenizer(file_os_path)
                    self:_process_write(reqpath, tkz:to_str(), file_os_path, mode)
                end
            end
        end

        for _, v in pairs(requires.eager) do
            process_require(v, 'eager')
        end

        for _, v in pairs(requires.lazy) do
            process_require(v, 'lazy')
        end
    end
end

---@param name string
---@param code string
---@param file_os_path string
---@param mode RequireTypes
function Bundler:_process_write(name, code, file_os_path, mode)
    print('Processing: ' .. file_os_path)
    self:_write_to_template(name, code, mode)
end

---@param path string
---@param content string
function Bundler:_write_to_file(path, content)
    local file, err = io.open(path, "w")
    if not file then
        error("\nError opening file: " .. err)
        return
    end
    file:write(content)
    file:close()
end

---@param name string
---@param content string
---@param mode RequireTypes
function Bundler:_write_to_template(name, content, mode)
    content = self:_escape_pattern(content)
    name = self:_escape_pattern(name)

    local code = ''
    if mode == 'eager' then
        code = self._eager_module:gsub('{importpath}', name):gsub('{code}', content)
    else
        code = self._lazy_module:gsub('{importpath}', name):gsub('{code}', content)
    end

    self._bundle_header = self._bundle_header .. code
end

---@param str string
function Bundler:_escape_pattern(str)
    str = str:gsub("([%[%]%.%+%-%*%?%^%$%(%)%{%}])", "%1")
    str = str:gsub("%%", "%%%%")
    return str
end

---@param lua_path string
---@return string
function Bundler:_path_fixer(lua_path)
    local separator = '/'

    if self:_get_os_name() == 'windows' then
        separator = '\\'
    end

    local result = lua_path:gsub('%.', separator)
    return result
end

---@param str string
---@return boolean
function Bundler:_starts_with_quote(str)
    return str:sub(1, 1) == "'" or str:sub(1, 1) == '"'
end

---@return 'windows' | 'linux'
function Bundler:_get_os_name()
    if package.config:sub(1, 1) == '\\' then
        return 'windows'
    end
    return 'linux'
end

---@return string
function Bundler:_getcwd()
    local cmd = "echo `pwd`"

    if self:_get_os_name() == 'windows' then
        cmd = 'cd'
    end

    local handle = io.popen(cmd)
    if not handle then
        error("\nCould not get current workdir")
    end
    local current_dir = handle:read("*a")
    handle:close()
    return current_dir
end

---@param ... string[]
---@return string
function Bundler:_path_join(...)
    local final = ''
    local separator = '/'

    if self:_get_os_name() == 'windows' then
        separator = '\\'
    end
    for _, v in pairs(...) do
        final = (final .. v .. separator):gsub('\n', '')
    end

    return final:gsub(separator .. "$", "")
end

---@param path string
---@return boolean
function Bundler:_file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

---@param path string
---@return Tokenizer
function Bundler:_get_tokenizer(path)
    local tokenizer = self._collected_modules[path]

    if not tokenizer then
        self._collected_modules[path] = Tokenizer:new(path)
        tokenizer = self._collected_modules[path]
    end

    return tokenizer
end

return Bundler:_init()

--#endregion
