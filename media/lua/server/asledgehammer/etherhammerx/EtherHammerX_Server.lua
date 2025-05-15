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
local LuaNetwork = require 'asledgehammer/network/LuaNetworkEvents';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';
local ZedUtils = require 'asledgehammer/util/ZedUtils';
local ANSIPrinter = require 'asledgehammer/util/ANSIPrinter';
local CACHE_DIR = Core.getMyDocumentFolder():gsub('\\', '/');

--- @type fun(minChars: number, maxChars?: number): string
local randomString = require 'asledgehammer/randomstring';

--- @type fun(code: string): string
local minify = (require 'asledgehammer/util/minify').minify;

local tableutils = require 'asledgehammer/util/tableutils';

--- @type fun(code: string, vars: table<string, {type: 'raw'|'function'|'func'|'table'|'number'|'string', value: any}>)
local inject = require 'asledgehammer/util/codeinject';

if not isServer() then return end

local isFatal = false;

local mod = 'EtherHammerX';
local printer = ANSIPrinter:new(mod);
local info = function(message, ...) printer:info(message, ...) end
local success = function(message, ...) printer:success(message, ...) end
local warn = function(message, ...) printer:warn(message, ...) end
local error = function(message, ...) printer:error(message, ...) end
local fatal = function(message, ...)
    isFatal = true;
    printer:fatal(message, ...);
end

local function printFatalMessage()
    fatal('%s encountered a fatal error. It is not running.', mod);
end

(function()
    local clientAPI = string.format(
        'print("[%s] :: !!! WARNING: CLIENT API MISSING. THINGS WILL BREAK !!!"); return {};', mod);
    local DEFAULT_KEY_CLIENT = 'local a=require"asledgehammer/randomstring"local b=nil;return function(c)if not b ' ..
        'then b=newrandom()b:seed(c:getSteamID())end;return a(32,48,b)end';
    local DEFAULT_KEY_SERVER = 'local a=require"asledgehammer/randomstring"return function(b)return a(32,48)end';

    local MOD_PATH = 'Zomboid/Lua/ModLoader/mods/EtherHammerX/';

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
        local dir = string.format('%s/Lua/ModLoader/mods/EtherHammerX/', CACHE_DIR);
        if not fileExists(dir) then
            fatal('Directory doesn\'t exist or is improperly installed: %s', dir);
            error('');
            error('In order to fix this, install the anti-cheat using the instructions here: %s%s',
                ANSIPrinter.KEYS['underline'] .. ANSIPrinter.KEYS['bright'],
                'https://github.com/asledgehammer/EtherHammerX'
            );
            error('1) Download the files, go to the "<> Code" button on the top-right and select "Download ZIP".');
            error('2) Create the directory: %s%s/Lua/ModLoader/mods/EtherHammerX/',
                ANSIPrinter.KEYS['underline'] .. ANSIPrinter.KEYS['bright'],
                CACHE_DIR
            );
            error('3) Extract and paste the contents in the folder.');
            error(
                'NOTE: Make sure the files are in that directory and not in a sub-directory from extracting the zip file.');
            error('');
            error('If you have any further questions, please visit my asledgehammer Discord server: %s%s',
                ANSIPrinter.KEYS['underline'] .. ANSIPrinter.KEYS['bright'],
                'https://discord.gg/u3vWvcPX8f'
            );
            error('');
            printFatalMessage();
            return;
        else
            success('EtherHammerX is properly installed.');
        end

        -- MARK: Config

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'config.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                fatal('File not installed: %s%s/%s%s',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR,
                    MOD_PATH,
                    'config.lua');
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

        if isFatal then
            printFatalMessage();
            return;
        end

        if variables.bad_packet_action == 'log' then
            warn();
            warn('!!! WARNING !!!');
            warn('Bad packets will not kick players. This means client-tampering and some cheats can evade this check.');
            warn('!!!!!!!!!!!!!!!');
            warn();
        end

        -- MARK: Keys

        local codeClientKey = DEFAULT_KEY_CLIENT;
        local codeServerKey = DEFAULT_KEY_SERVER;
        local clientKeyValid = false;
        local serverKeyValid = false;

        local clientKeyPath = string.format('keys/%s_client.lua', tostring(variables.key));
        ModLoader.requestServerFile(mod, clientKeyPath, function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                warn('The file %s%s/%s%s is missing. Using Fallback..',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, clientKeyPath,
                    ANSIPrinter.KEYS['remove_underline']
                );
                return;
            end
            if not data or string.trim(data) == '' then
                warn('The file %s%s/%s%s exists, but is empty. Using Fallback..',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, clientKeyPath,
                    ANSIPrinter.KEYS['remove_underline']);
                return;
            end
            local code = minify(data);
            -- Test compiling and checking type for return of client-key function.
            if type(loadstring(code)()) ~= "function" then
                warn('The file %s%s/%s%s exists, but doesn\'t return a function. Using Fallback..',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, clientKeyPath,
                    ANSIPrinter.KEYS['remove_underline']
                );
                return;
            end
            codeClientKey = code;
            clientKeyValid = true;
        end);

        if clientKeyValid then
            local serverKeyPath = string.format('keys/%s_server.lua', variables.key);
            ModLoader.requestServerFile(mod, serverKeyPath, function(result, data)
                if result == ModLoader.RESULT_FILE_NOT_FOUND then
                    warn('The file %s%s/%s%s is missing. Using Fallback..',
                        ANSIPrinter.KEYS['underline'],
                        CACHE_DIR, serverKeyPath,
                        ANSIPrinter.KEYS['remove_underline']
                    );
                    return;
                end
                if not data or string.trim(data) == '' then
                    warn('The file %s%s/%s%s exists, but is empty. Using Fallback..',
                        ANSIPrinter.KEYS['underline'],
                        CACHE_DIR, serverKeyPath,
                        ANSIPrinter.KEYS['remove_underline']
                    );
                    return;
                end
                local code = minify(data);
                -- Test compiling and checking type for return of client-key function.
                if type(loadstring(code)()) ~= 'function' then
                    warn('The file %s%s/%s%s exists, but doesn\'t return a function. Using Fallback..',
                        ANSIPrinter.KEYS['underline'],
                        CACHE_DIR, serverKeyPath,
                        ANSIPrinter.KEYS['remove_underline']
                    );
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
                info('Loading module: %s..', moduleCfg.name);
                local func = 'return function() end';
                local moduleClientPath = string.format('modules/%s.lua', moduleID);
                ModLoader.requestServerFile(mod, moduleClientPath, function(result, data)
                    if result == ModLoader.RESULT_FILE_NOT_FOUND then
                        warn('File not installed: %s%s/Lua/ModLoader/mods/%s/%s',
                            ANSIPrinter.KEYS['underline'],
                            CACHE_DIR, mod, moduleClientPath);
                        return;
                    end
                    if not data or string.trim(data) == '' then
                        warn('The file exists, but is empty: %s%s/Lua/ModLoader/mods/%s/%s%s (Using Fallback..)',
                            ANSIPrinter.KEYS['underline'],
                            CACHE_DIR, mod, moduleClientPath,
                            ANSIPrinter.KEYS['remove_underline']
                        );
                        return;
                    end
                    -- Pre-escape any double-quotes for reapplciation when injected.
                    data = string.gsub(data, '\\', '\\\\');
                    local code = string.gsub(minify(data), '"', '\\"');
                    info('Compiling module: %s..', moduleCfg.name);
                    -- Test compiling and checking type for return of a function.
                    if type(loadstring(code)()) ~= 'function' then
                        warn(
                            'The file exists, but doesn\'t return a function: %s%s/Lua/ModLoader/mods/%s/%s%s (Using Fallback..)',
                            ANSIPrinter.KEYS['underline'],
                            CACHE_DIR, mod, moduleClientPath,
                            ANSIPrinter.KEYS['remove_underline']
                        );
                        return;
                    end
                    -- Embed quotes in module code.
                    func = minify(code);
                end);
                if func then
                    local moduleCode = string.format('%s={code=loadstring("%s")(),options=%s,name="%s",runOnce=%s}',
                        moduleID,
                        func,
                        tableutils.tableToString(moduleCfg.options or {}),
                        moduleCfg.name,
                        tostring(moduleCfg.runOnce)
                    );
                    if clientModulesCode == '' then
                        clientModulesCode = moduleCode;
                    else
                        clientModulesCode = string.format('%s,%s', clientModulesCode, moduleCode);
                    end
                    success('Module loaded: %s', moduleCfg.name);
                end
            else
                warn('Skipping module: %s (not enabled) ..', moduleCfg.name);
            end
        end

        injectVariables['modules'] = { type = 'raw', value = string.format('{%s}', clientModulesCode) };

        -- MARK: API

        -- Load the server-side code and run it.
        ModLoader.requestServerFile(mod, 'client_api.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                fatal('File not installed: %s%s/Lua/ModLoader/mods/%s/%s',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, mod, 'client_api.lua'
                );
                return;
            end
            -- (Substitute back-slash literals to prevent code from breaking)
            data = string.gsub(data, '\\', '\\\\');
            clientAPI = minify(data);
        end);

        if isFatal then
            printFatalMessage();
            return;
        end

        -- MARK: Server

        -- Create our live / modified variables lua code to inject into server.lua.

        variables.config = string.format('return %s;', tableutils.tableToString(variables));

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'client.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                fatal('File not installed: %s%s/Lua/ModLoader/mods/%s/%s',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, mod, 'client.lua'
                );
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

        if isFatal then
            printFatalMessage();
            return;
        end

        -- MARK: Client

        -- Load the server-side code and run it.
        ModLoader.requestServerFile(mod, 'server.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                fatal('File not installed: %s%s/Lua/ModLoader/mods/%s/%s',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, mod, 'server.lua'
                );
                return;
            end
            info('Injecting config variables: server.lua');
            data = inject(data, injectVariables);
            data = inject(data, {
                client_key_function = { type = 'function', value = funcVariables.client_key_function },
                server_key_function = { type = 'function', value = funcVariables.server_key_function },
            });
            local result = pcall(function()
                loadstring(data, 'EtherHammerX_Server')();
            end);
            if not result then
                fatal('Failed to compile %s%s/Lua/ModLoader/mods/%s/%s',
                    ANSIPrinter.KEYS['underline'],
                    CACHE_DIR, mod, 'server.lua'
                );
                return;
            end
            success('Successfully loaded.');
        end);

        if isFatal then
            printFatalMessage();
            return;
        end

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
