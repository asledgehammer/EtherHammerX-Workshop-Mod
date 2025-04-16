---[[
--- EtherHammerX - Server bootloader. Handles loading the anti-cheat framework and prepares it by injecting variables and
--- minifying / obfuscating the code.
---
--- @author asledgehammer, JabDoesThings 2025
---]]

local DEBUG = false;

--- @alias ModLoaderCallback fun(result: number, data: string | nil): string | nil

--- @type {RESULT_FILE_NOT_FOUND: number, requestServerFile: fun(mod: string, path: string, cacheOrResult: boolean | ModLoaderCallback, result?: ModLoaderCallback): void}
local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';
local LuaNetwork = require 'asledgehammer/network/LuaNetworkEvents';
local ZedUtils = require 'asledgehammer/util/ZedUtils';

--- @type fun(minChars: number, maxChars?: number): string
local randomString = require 'asledgehammer/randomstring';

--- @type fun(code: string): string
local minify = (require 'asledgehammer/util/minify').minify;

local tableutils = require 'asledgehammer/util/tableutils';

--- @type fun(code: string, vars: table<string, {type: 'raw'|'function'|'func'|'table'|'number'|'string', value: any}>)
local inject = require 'asledgehammer/util/codeinject';

if not isServer() then return end

local mod = 'EtherHammerX';

--- @param message? string
local info = function(message)
    if not message then
        print('[' .. mod .. '] :: ');
    else
        print('[' .. mod .. '] :: ' .. tostring(message));
    end
end

(function()
    local clientAPI = 'print("[EtherHammerX] :: !!! WARNING: CLIENT API MISSING. THINGS WILL BREAK !!!"); return {};';
    local DEFAULT_KEY_CLIENT = 'local a=require"asledgehammer/randomstring"local b=nil;return function(c)if not b ' ..
        'then b=newrandom()b:seed(c:getSteamID())end;return a(32,48,b)end';
    local DEFAULT_KEY_SERVER = 'local a=require"asledgehammer/randomstring"return function(b)return a(32,48)end';

    local variables = {
        key = 'basic',
        modules = { etherhack = { name = 'etherhack', runOnce = false } },
    };

    local injectVariables = {

        -- Initial key
        handshake_key = { type = 'string', value = randomString(32, 48) },

        -- Injected commands
        handshake_request_command = { type = 'string', value = randomString(32, 48) },
        heartbeat_response_command = { type = 'string', value = randomString(32, 48) },
        heartbeat_request_command = { type = 'string', value = randomString(32, 48) },
        report_command = { type = 'string', value = randomString(32, 48) },
        request_player_info_command = { type = 'string', value = randomString(32, 48) },

        -- Command module
        module_id = { type = 'string', value = randomString(32, 48) },

        -- Default settings
        time_to_greet = { type = 'number', value = 10 },
        time_to_verify = { type = 'number', value = 120 },
        time_to_heartbeat = { type = 'number', value = 20 },
        time_to_tick = { type = 'number', value = 5 },
        should_heartbeat = { type = 'boolean', value = true },
        submit_ticket_on_kick = { type = 'boolean', value = true },
        bad_packet_action = { type = 'string', value = 'kick' },
    };

    local funcVariables = {
        client_key_function = { type = 'func', value = DEFAULT_KEY_CLIENT },
        server_key_function = { type = 'func', value = DEFAULT_KEY_SERVER },
    };

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
                    local nameUpper = string.upper(name);
                    if config[nameUpper] ~= nil then
                        if config[nameUpper] == '' then
                            variables[name] = defaultValue;
                            injectVariables[name] = { type = type, value = defaultValue };
                            return;
                        end
                        variables[name] = config[nameUpper];
                        injectVariables[name] = { type = type, value = config[nameUpper] };
                    else
                        variables[name] = defaultValue;
                        injectVariables[name] = { type = type, value = defaultValue };
                    end
                end
            end

            load('key', 'string', 'basic');
            load('handshake_key', 'string', randomString(8, 32));
            load('modules', 'table', { basic = { name = 'EtherHack', options = {} } });
            load('should_heartbeat', 'boolean', true);
            load('time_to_greet', 'number', 10);
            load('time_to_verify', 'number', 120);
            load('time_to_heartbeat', 'number', 20);
            load('time_to_tick', 'number', 5);
            load('bad_packet_action', 'string', 'kick');
        end);

        if variables.bad_packet_action == 'log' then
            info();
            info('!!! WARNING !!!');
            info('Bad packets will not kick players. This means client-tampering and some cheats can evade this check.');
            info('!!!!!!!!!!!!!!!');
            info();
        end

        -- MARK: Keys

        local codeClientKey = DEFAULT_KEY_CLIENT;
        local codeServerKey = DEFAULT_KEY_SERVER;
        local clientKeyValid = false;
        local serverKeyValid = false;

        local clientKeyPath = 'keys/' .. variables.key .. '_client.lua';
        ModLoader.requestServerFile(mod, clientKeyPath, function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('The file "' .. clientKeyPath .. '" is missing. Using Fallback..');
                return;
            end
            if not data or string.trim(data) == '' then
                info('The file "' .. clientKeyPath .. '" exists, but is empty. Using Fallback..');
                return;
            end
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
            local serverKeyPath = 'keys/' .. variables.key .. '_server.lua';
            ModLoader.requestServerFile(mod, serverKeyPath, function(result, data)
                if result == ModLoader.RESULT_FILE_NOT_FOUND then
                    info('The file "' .. serverKeyPath .. '" is missing. Using Fallback..');
                    return;
                end
                if not data or string.trim(data) == '' then
                    info('The file "' .. serverKeyPath .. '" exists, but is empty. Using Fallback..');
                    return;
                end
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

        funcVariables.client_key_function = codeClientKey;
        funcVariables.server_key_function = codeServerKey;

        -- MARK: Modules

        local clientModulesCode = '';

        for moduleID, moduleCfg in pairs(variables.modules) do
            if moduleCfg.runOnce == nil then
                moduleCfg.runOnce = false;
            end

            -- Skip disabled module(s).
            if moduleCfg.enable == nil or moduleCfg.enable then
                info("Loading module: " .. moduleCfg.name .. '..');
                local func = 'return function() end';
                local moduleClientPath = 'modules/' .. moduleID .. '.lua';
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
                    data = string.gsub(data, '\\', '\\\\');
                    local code = string.gsub(minify(data), '"', '\\"');
                    info("Compiling module: " .. moduleCfg.name .. '..');
                    -- Test compiling and checking type for return of a function.
                    if type(loadstring(code)()) ~= "function" then
                        info('The file "' ..
                            moduleClientPath .. '" exists, but doesn\'t return a function. Using Fallback..');
                        return;
                    end
                    -- Embed quotes in module code.
                    func = minify(code);
                end);
                if func then
                    local moduleCode = moduleID ..
                        '={code=loadstring("' ..
                        func ..
                        '")(), options=' ..
                        tableutils.tableToString(moduleCfg.options or {}) ..
                        ',name="' .. moduleCfg.name .. '",runOnce=' .. tostring(moduleCfg.runOnce) .. '}';
                    if clientModulesCode == '' then
                        clientModulesCode = moduleCode;
                    else
                        clientModulesCode = clientModulesCode .. ',' .. moduleCode;
                    end
                    info("Module loaded: " .. moduleCfg.name);
                end
            else
                info("Skipping module: " .. moduleCfg.name .. ' (not enabled) ..');
            end
        end

        injectVariables['modules'] = { type = 'raw', value = '{' .. clientModulesCode .. '}' };

        -- MARK: API

        -- Load the server-side code and run it.
        ModLoader.requestServerFile(mod, 'client_api.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/client_api.lua');
                return;
            end
            -- (Substitute back-slash literals to prevent code from breaking)
            data = string.gsub(data, '\\', '\\\\');
            clientAPI = minify(data);
        end);

        -- MARK: Server

        -- Create our live / modified variables lua code to inject into server.lua.

        variables.config = 'return ' .. tableutils.tableToString(variables) .. ';';

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'client.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/client.lua');
                return;
            end
            info('Injecting config variables: client.lua..');
            data = inject(data, injectVariables);
            data = inject(data, { client_api = { type = 'table', value = clientAPI } });
            -- !!! Only inject the client key-fragment function to the client. !!!
            data = inject(data,
                { client_key_function = { type = 'function', value = funcVariables.client_key_function } });
            -- If the server is debugging their anti-cheat framework, don't minify the package.
            if not variables.debug then
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
                client_key_function = { type = 'function', value = funcVariables.client_key_function },
                server_key_function = { type = 'function', value = funcVariables.server_key_function }
            });
            loadstring(data)();
            info('Successfully loaded.');
        end);

        if DEBUG then
            LuaNetwork.addClientListener(function(module, command, player, args)
                ZedUtils.printLuaCommand(module, command, player, args);
            end);
        end
    end

    --- Protective padding for one-trigger self-removed functions.
    Events.OnServerStarted.Add(function() end);
    Events.OnServerStarted.Add(onServerStart);
end)();
