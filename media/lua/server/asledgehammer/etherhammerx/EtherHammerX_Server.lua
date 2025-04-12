---[[
--- EtherHammerX - Server bootloader. Handles loading the anti-cheat framework and prepares it by injecting variables and
--- minifying / obfuscating the code.
---
--- @author asledgehammer, JabDoesThings 2025
---]]

--- @alias ModLoaderCallback fun(result: number, data: string | nil): string | nil

--- @type {RESULT_FILE_NOT_FOUND: number, requestServerFile: fun(mod: string, path: string, cacheOrResult: boolean | ModLoaderCallback, result?: ModLoaderCallback): void}
local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';

--- @type fun(minChars: number, maxChars?: number): string
local randomString = require 'asledgehammer/randomstring';

--- @type fun(code: string): string
local minify = (require 'asledgehammer/util/minify').minify;

local tableutils = require 'asledgehammer/util/tableutils';

--- @type fun(code: string, vars: table<string, {type: 'raw'|'function'|'func'|'table'|'number'|'string', value: any}>)
local inject = require 'asledgehammer/util/codeinject';

if not isServer() then return end

local mod = 'EtherHammerX';
local info = function(msg)
    print('[' .. mod .. '] :: ' .. msg);
end

(function()
    -- NOTE: Putting this here due to an update where the code itself might not have `client_api.lua` yet.
    local clientAPI =
        "local a=false;local b={}function b.isDisconnected()return a end;function b.disconnect()a=true;setGameSpeed(1)" ..
        "pauseSoundAndMusic()setShowPausedMessage(true)getCore():quit()end;function b.getGlobalClasses()local c={}for " ..
        "d,e in pairs(_G)do if type(e)=='table'and e.Type~=nil then table.insert(c,{globalName=d,typeName=e.Type})end " ..
        "end;table.sort(c,function(f,g)return f.globalName<g.globalName end)return c end;function b.getGlobalTables()" ..
        "local c={}for d,e in pairs(_G)do if type(e)=='table'then table.insert(c,d)end end;table.sort(c,function(f,g)" ..
        "return f:upper()<g:upper()end)return c end;function b.getGlobalFunctions()local c={}for d,e in pairs(_G)do if " ..
        "type(e)=='function'and string.find(tostring(e),'function ')==1 then table.insert(c,d)end end;table.sort(c," ..
        "function(f,g)return f:upper()<g:upper()end)return c end;function b.arrayContains(c,e)for h,i in ipairs(c)do " ..
        "if e==i then return true end end;return false end;function b.anyExists(j,k)for l=1,#k do if b.arrayContains" ..
        "(j,k[l])then return true end end;return false end;function b.printGlobalClasses(m)m=m or b.getGlobalClasses()" ..
        "local n='Global Class(es) ('..tostring(#m)..'):\\n'for h,o in ipairs(m)do n=n..'\\t'..tostring(o.globalName)..' " ..
        "(class.Type = '..tostring(o.typeName)..')\\n'end;print(n)end;function b.printGlobalTables(p)p=p or " ..
        "b.getGlobalTables()local n='Global Table(s) ('..tostring(#p)..'):\\n'for h,d in ipairs(p)do n=n..'\\t'.." ..
        "tostring(d)..'\\n'end;print(n)end;function b.printGlobalFunctions(q)q=q or b.getGlobalFunctions()local " ..
        "n='Global function(s) ('..tostring(#q)..'):\\n'for h,r in ipairs(q)do n=n..'\\t'..tostring(r)..'\\n'end;" ..
        "print(n)end;function b.ticketExists(s,t,u)local v=function()end;v=function(w)Events.ViewTickets.Remove(v)local " ..
        "x=w:size()-1;for l=0,x do local y=w:get(l)if y:getAuthor()==s and t==y:getMessage()then u(true)return end end;" ..
        "u(false)end;Events.ViewTickets.Add(v)getTickets(s)end;function b.submitTicket(t,u)local z=getPlayer()local " ..
        "A=z:getUsername()b.ticketExists(A,t,function(B)if not B then addTicket(A,t,-1)end;u()end)end;function " ..
        "b.report(type,C,D)local t=tostring(type)if C then t=t..' ('..tostring(C)..')'end;print('[EtherHammerX] :: '..t)" ..
        "if D then b.disconnect()end end;return b";

    local DEFAULT_KEY_CLIENT = 'local a=require"asledgehammer/randomstring"local b=nil;return function(c)if not b then ' ..
        'b=newrandom()b:seed(c:getSteamID())end;return a(32,48,b)end';
    local DEFAULT_KEY_SERVER = 'local a=require"asledgehammer/randomstring"return function(b)return a(32,48)end';

    local variables = {
        KEY = 'basic',
        MODULES = { etherhack = { name = 'etherhack', runOnce = false } },
    };

    local injectVariables = {

        -- Initial key
        HANDSHAKE_KEY = { type = 'string', value = randomString(32, 48) },

        -- Injected commands
        HANDSHAKE_REQUEST_COMMAND = { type = 'string', value = randomString(32, 48) },
        HEARTBEAT_RESPONSE_COMMAND = { type = 'string', value = randomString(32, 48) },
        HEARTBEAT_REQUEST_COMMAND = { type = 'string', value = randomString(32, 48) },
        REPORT_COMMAND = { type = 'string', value = randomString(32, 48) },
        REQUEST_PLAYER_INFO_COMMAND = { type = 'string', value = randomString(32, 48) },

        -- Command module
        MODULE_ID = { type = 'string', value = randomString(32, 48) },

        -- Default settings
        TIME_TO_GREET = { type = 'number', value = 10 },
        TIME_TO_VERIFY = { type = 'number', value = 120 },
        TIME_TO_HEARTBEAT = { type = 'number', value = 20 },
        TIME_TO_TICK = { type = 'number', value = 5 },
        SHOULD_HEARTBEAT = { type = 'boolean', value = true },
        SUBMIT_TICKET_ON_KICK = { type = 'boolean', value = true },

    };

    local funcVariables = {
        CLIENT_KEY_FUNCTION = { type = 'func', value = DEFAULT_KEY_CLIENT },
        SERVER_KEY_FUNCTION = { type = 'func', value = DEFAULT_KEY_SERVER },
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
                    variables[name] = defaultValue;
                    injectVariables[name] = { type = type, value = defaultValue };
                end
            end

            load('HANDSHAKE_KEY', 'string', randomString(8, 32));
            load('MODULES', 'table', { basic = { name = 'EtherHack', options = {} } });
            load('SHOULD_HEARTBEAT', 'boolean', true);
            load('TIME_TO_GREET', 'number', 10);
            load('TIME_TO_VERIFY', 'number', 120);
            load('TIME_TO_HEARTBEAT', 'number', 20);
            load('TIME_TO_TICK', 'number', 5);
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

        injectVariables['MODULES'] = { type = 'raw', value = '{' .. clientModulesCode .. '}' };

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

        variables.CONFIG = 'return ' .. tableutils.tableToString(variables) .. ';';

        -- Load the client-side code and cache it as encrypted.
        ModLoader.requestServerFile(mod, 'client.lua', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND or not data or string.trim(data) == '' then
                info('File not installed: Zomboid/Lua/ModLoader/mods/EtherHammerX/client.lua');
                return;
            end
            info('Injecting config variables: client.lua..');
            data = inject(data, injectVariables);
            data = inject(data, { CLIENT_API = { type = 'table', value = clientAPI } });
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
