--- @alias ModLoaderCallback fun(result: number, data: string | nil): string | nil

--- @type {RESULT_FILE_NOT_FOUND: number, requestServerFile: fun(mod: string, path: string, cacheOrResult: boolean | ModLoaderCallback, result?: ModLoaderCallback): void}
local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';

--- @type fun(minChars: number, maxChars?: number): string
local randomString = require 'asledgehammer/randomstring';

--- @type fun(code: string): string
local minify = (require 'asledgehammer/util/minify').minify;

if not isServer() then return end

(function()
    local DEFAULT_KEY_CLIENT = 'function(a) return a:getOnlineID()..\'_\'..a:getUsername() end';
    local DEFAULT_KEY_SERVER = 'function(a) return a:getOnlineID()..\'_\'..getTimeInMillis() end';

    local injectVariables = {
        HANDSHAKE_KEY = { type = 'string', value = randomString(32, 48) },
        HANDSHAKE_REQUEST_COMMAND = { type = 'string', value = randomString(32, 48) },
        HEARTBEAT_RESPONSE_COMMAND = { type = 'string', value = randomString(32, 48) },
        HEARTBEAT_REQUEST_COMMAND = { type = 'string', value = randomString(32, 48) },
        MODULE_ID = { type = 'string', value = randomString(32, 48) },
        TIME_TO_GREET = { type = 'number', value = 10 },
        TIME_TO_VERIFY = { type = 'number', value = 120 },
        TIME_TO_HEARTBEAT = { type = 'number', value = 20 },
        TIME_TO_TICK = { type = 'number', value = 5 },
        SHOULD_HEARTBEAT = { type = 'boolean', value = true },
        SUBMIT_TICKET_ON_KICK = { type = 'boolean', value = true },
    };

    local variables = {
        KEY = 'basic',
        MODULES = {
            etherhack = {
                name = 'etherhack',
                runOnce = false,
            }
        },
    };

    local funcVariables = {
        CLIENT_KEY_FUNCTION = { type = 'func', value = DEFAULT_KEY_CLIENT },
        SERVER_KEY_FUNCTION = { type = 'func', value = DEFAULT_KEY_SERVER },
    };

    local mod = 'EtherHammerX';

    local info = function(msg)
        print('[' .. mod .. '] :: ' .. msg);
    end

    local function isArray(t)
        local i = 0;
        for _ in pairs(t) do
            i = i + 1;
            if t[i] == nil then return false end
        end
        return true;
    end

    --- @type fun(t: table): string
    local tableToString;
    --- @type fun(v: any, encaseStrings?: boolean): string
    local anyToString;

    anyToString = function(v, encaseStrings)
        if encaseStrings == nil then encaseStrings = true end
        local type = type(v);
        if type == 'number' then
            return tostring(v);
        elseif type == 'boolean' then
            return tostring(v);
        elseif type == 'nil' then
            return 'nil';
        elseif type == 'table' then
            return tableToString(v);
        else
            if encaseStrings then
                return '"' .. tostring(v) .. '"';
            else
                return tostring(v);
            end
        end
    end

    tableToString = function(t)
        local s = '';
        if isArray(t) then
            for _, v in ipairs(t) do
                local vStr = anyToString(v);
                if s == '' then s = vStr else s = s .. ',' .. vStr end
            end
        else
            for k, v in pairs(t) do
                local vStr = anyToString(v);
                if s == '' then
                    s = s .. k .. '=' .. vStr;
                else
                    s = s .. ',' .. k .. '=' .. vStr;
                end
            end
        end
        return '{' .. s .. '}';
    end

    --- @param code string
    --- @param vars table<string, {type: 'raw'|'function'|'func'|'table'|'number'|'string', value: any}>
    ---
    --- @return string
    local function inject(code, vars)
        for id, var in pairs(vars) do
            if var.type == 'function' or var.type == 'func' then
                local literalValue = 'loadstring("' .. string.gsub(var.value, '"', '\\"') .. '")()';
                code = string.gsub(code, '{%s*func%s*=%s*"' .. id .. '"%s*}', literalValue);
                code = string.gsub(code, "{%s*func%s*=%s*'" .. id .. "'%s*}", literalValue);
            elseif var.type == 'table' then
                if type(var.value) == 'string' then
                    local literalValue = 'loadstring("' .. string.gsub(var.value, '"', '\\"') .. '")()';
                    code = string.gsub(code, '{%s*table%s*=%s*"' .. id .. '"%s*}', literalValue);
                    code = string.gsub(code, "{%s*table%s*=%s*'" .. id .. "'%s*}", literalValue);
                elseif type(var.value) == 'table' then
                    local literalValue = tableToString(var.value);
                    code = string.gsub(code, '{%s*table%s*=%s*"' .. id .. '"%s*}', literalValue);
                    code = string.gsub(code, "{%s*table%s*=%s*'" .. id .. "'%s*}", literalValue);
                end
            elseif var.type == 'number' then
                local literalValue = tostring(var.value);
                code = string.gsub(code, '{%s*number%s*=%s*"' .. id .. '"%s*}', literalValue);
                code = string.gsub(code, "{%s*number%s*=%s*'" .. id .. "'%s*}", literalValue);
            elseif var.type == 'boolean' then
                local literalValue = tostring(var.value);
                code = string.gsub(code, '{%s*boolean%s*=%s*"' .. id .. '"%s*}', literalValue);
                code = string.gsub(code, "{%s*boolean%s*=%s*'" .. id .. "'%s*}", literalValue);
            elseif var.type == 'raw' then
                local literalValue = tostring(var.value);
                code = string.gsub(code, '{%s*raw%s*=%s*"' .. id .. '"%s*}', literalValue);
                code = string.gsub(code, "{%s*raw%s*=%s*'" .. id .. "'%s*}", literalValue);
            else
                local literalValue = '"' .. tostring(var.value) .. '"';
                code = string.gsub(code, '{%s*%w+%s*=%s*"' .. id .. '"%s*}', literalValue);
                code = string.gsub(code, "{%s*%w+%s*=%s*'" .. id .. "'%s*}", literalValue);
            end
        end
        return code;
    end

    local onServerStart = function()
        -- MARK: Config

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'config.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/config.lua');
                return;
            end

            info('Loading config.lua..');
            local config = loadstring(data)();

            local load = function(name, type, defaultValue)
                if config[name] ~= nil then
                    if config[name] == '' then
                        variables[name] = defaultValue;
                        injectVariables[name] = { type = type, value = defaultValue };
                        return;
                    end
                    variables[name] = config[name];
                    injectVariables[name] = { type = type, value = config[name] };
                else
                    variables[name] = defaultValue;
                    injectVariables[name] = { type = type, value = defaultValue };
                end
            end

            load('HANDSHAKE_KEY', 'string', randomString(8, 32));
            load('HANDSHAKE_REQUEST_COMMAND', 'string', randomString(8, 32));
            load('HEARTBEAT_RESPONSE_COMMAND', 'string', randomString(8, 32));
            load('HEARTBEAT_REQUEST_COMMAND', 'string', randomString(8, 32));
            load('MODULE_ID', 'string', randomString(8, 32));
            load('TIME_TO_GREET', 'number', 10);
            load('TIME_TO_VERIFY', 'number', 120);
            load('SHOULD_HEARTBEAT', 'boolean', true);
            load('SUBMIT_TICKET_ON_KICK', 'boolean', true);
            load('TIME_TO_HEARTBEAT', 'number', 20);
            load('TIME_TO_TICK', 'number', 5);
            load('MODULES', 'table', { basic = { name = 'EtherHack', options = {} } });
        end);

        -- MARK: Keys

        local codeClientKey = DEFAULT_KEY_CLIENT;
        local codeServerKey = DEFAULT_KEY_SERVER;
        local clientKeyValid = false;
        local serverKeyValid = false;
        local clientKeyPath = 'keys/' .. variables.KEY .. '_client.lua';
        ModLoader.requestServerFile(mod, clientKeyPath, function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('The file "' .. clientKeyPath .. '" is missing. Using Fallback..');
                return;
            end
            if not data or string.trim(data) == '' then
                info('The file "' .. clientKeyPath .. '" exists, but is empty. Using Fallback..');
                return;
            end
            -- We pre-escape any double-quotes for reapplciation when injected.
            -- local code = string.gsub(minify(data), '"', '\\"');
            local code = minify(data);

            -- Test compiling and checking type for return of client-key function.
            if type(loadstring(code)()) ~= "function" then
                info('The file "' .. clientKeyPath .. '" exists, but doesn\'t return a function. Using Fallback..');
                return;
            end

            codeClientKey = code;
            clientKeyValid = true;
        end);

        if clientKeyValid then
            local serverKeyPath = 'keys/' .. variables.KEY .. '_server.lua';
            ModLoader.requestServerFile(mod, serverKeyPath, function(result, data)
                if result == ModLoader.RESULT_FILE_NOT_FOUND then
                    info('The file "' .. serverKeyPath .. '" is missing. Using Fallback..');
                    return;
                end
                if not data or string.trim(data) == '' then
                    info('The file "' .. serverKeyPath .. '" exists, but is empty. Using Fallback..');
                    return;
                end
                -- -- We pre-escape any double-quotes for reapplciation when injected.
                -- local code = string.gsub(minify(data), '"', '\\"');
                local code = minify(data);

                -- Test compiling and checking type for return of client-key function.
                if type(loadstring(code)()) ~= "function" then
                    info('The file "' .. serverKeyPath .. '" exists, but doesn\'t return a function. Using Fallback..');
                    return;
                end

                codeServerKey = code;
                serverKeyValid = true;
            end);
        end

        if not clientKeyValid or not serverKeyValid then
            codeClientKey = DEFAULT_KEY_CLIENT;
            codeServerKey = DEFAULT_KEY_SERVER;
        end

        funcVariables.CLIENT_KEY_FUNCTION = codeClientKey;
        funcVariables.SERVER_KEY_FUNCTION = codeServerKey;

        -- MARK: Modules

        local clientModulesCode = '';

        for moduleID, moduleCfg in pairs(variables.MODULES) do
            info("Loading module: " .. moduleCfg.name .. '..');
            local func = 'return function() end';
            local moduleClientPath = 'modules/' .. moduleID .. '_client.lua';
            ModLoader.requestServerFile(mod, moduleClientPath, function(result, data)
                if result == ModLoader.RESULT_FILE_NOT_FOUND then
                    info('The file "' .. moduleClientPath .. '" is missing.');
                    return;
                end
                if not data or string.trim(data) == '' then
                    info('The file "' .. moduleClientPath .. '" exists, but is empty. Using Fallback..');
                    return;
                end

                -- Pre-escape any double-quotes for reapplciation when injected.
                local code = string.gsub(minify(data), '"', '\\"');

                info("Compiling module: " .. moduleCfg.name .. '..');
                -- Test compiling and checking type for return of a function.
                if type(loadstring(code)()) ~= "function" then
                    info('The file "' .. moduleClientPath .. '" exists, but doesn\'t return a function. Using Fallback..');
                    return;
                end
                -- Embed quotes in module code.
                func = minify(code);
            end);

            if func then
                local moduleCode = moduleID ..
                    '={code=loadstring("' ..
                    func .. '")(), options='.. tableToString(moduleCfg.options or {})..',name="' .. moduleCfg.name .. '",runOnce=' .. tostring(moduleCfg.runOnce) .. '}';
                if clientModulesCode == '' then
                    clientModulesCode = moduleCode;
                else
                    clientModulesCode = clientModulesCode .. ',' .. moduleCode;
                end
                info("Module loaded: " .. moduleCfg.name);
            end
        end

        injectVariables['MODULES'] = { type = 'raw' , value = '{' .. clientModulesCode .. '}' };

        -- MARK: Server

        -- Create our live / modified variables lua code to inject into server.lua.

        variables.CONFIG = 'return ' .. tableToString(variables) .. ';';

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'client.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/client.lua');
                return;
            end

            info('Injecting config variables: client.lua..');
            data = inject(data, injectVariables);
            -- !!! Only inject the client key-fragment function to the client. !!!
            data = inject(data,
                { CLIENT_KEY_FUNCTION = { type = 'function', value = funcVariables.CLIENT_KEY_FUNCTION } });

            -- If the server is debugging their anti-cheat framework, don't minify the package.
            if not variables.DEBUG then
                data = minify(data);
            end

            -- Return the encrypted form of the code to cache it for the client on request.
            return ZedCrypt.encrypt(data, '__EtherHammerX__');
        end);

        -- MARK: Client

        -- Load the server-side code and run it.
        ModLoader.requestServerFile(mod, 'server.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/server.lua');
                return;
            end

            info('Injecting config variables: server.lua');
            data = inject(data, injectVariables);
            data = inject(data, {
                CLIENT_KEY_FUNCTION = { type = 'function', value = funcVariables.CLIENT_KEY_FUNCTION },
                SERVER_KEY_FUNCTION = { type = 'function', value = funcVariables.SERVER_KEY_FUNCTION }
            });

            loadstring(data)();
            info('Successfully loaded.');
        end);
    end

    Events.OnServerStarted.Add(onServerStart);
end)();
