local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';
local ZedUtils = require 'asledgehammer/util/ZedUtils';

(function()
    local mod = 'EtherHammerX';

    local info = function(msg)
        print('[' .. mod .. '] :: ' .. msg);
    end

    local onGameStart = function()
        -- Request the client-code from the server.
        ModLoader.requestServerFile('EtherHammerX', 'EtherHammerX_Client.lua', true, function(module, path, result, data)
            -- Handle non-installed / missing result.
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('File not installed on server. Ignoring..');
                return;
            end

            -- Unpackage the code.
            info('Unpacking..');
            local timeThen = getTimeInMillis();
            local decryptedData = ZedCrypt.decrypt(data, 'EtherHammerX');
            local delta = getTimeInMillis() - timeThen;
            info('Unpacked in ' .. delta .. ' ms.');

            -- Invoke the code.
            loadstring(decryptedData)();
        end);
    end

    -- Delay the request by 5 or so ticks to give time for LuaNet to start.
    ZedUtils.delay(5, onGameStart);
end)();
