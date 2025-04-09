---[[
--- EtherHammerX - Client bootloader. Handles requesting and loading the anti-cheat framework.
---
--- @author asledgehammer, JabDoesThings 2025
---]]

local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';

local mod = 'EtherHammerX';
local info = function(msg)
    print('[' .. mod .. '] :: ' .. msg);
end

(function()
    local onGameStart = function()
        ModLoader.requestServerFile('EtherHammerX', 'client', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('File not installed on server. The client will likely be kicked for not loading the anti-cheat.');
                return;
            end
            loadstring(ZedCrypt.decrypt(data, '__EtherHammerX__'))();
        end);
    end
    Events.OnLuaNetworkConnected.Add(onGameStart);
end)();
