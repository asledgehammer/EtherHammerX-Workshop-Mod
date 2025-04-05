local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';

(function()
    local mod = 'EtherHammerX';
    local info = function(msg)
        print('[' .. mod .. '] :: ' .. msg);
    end
    local onGameStart = function()
        -- Request the client-code from the server.
        ModLoader.requestServerFile('EtherHammerX', 'client', function(result, data)
            -- Handle non-installed / missing result.
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('File not installed on server. Ignoring..');
                return;
            end
            -- Invoke the code.
            loadstring(ZedCrypt.decrypt(data, '__EtherHammerX__'))();
        end);
    end
    Events.OnLuaNetworkConnected.Add(onGameStart);
end)();
