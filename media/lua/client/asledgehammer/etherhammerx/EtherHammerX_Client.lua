---[[
--- EtherHammerX - Client bootloader. Handles requesting and loading the anti-cheat framework.
---
--- @author asledgehammer, JabDoesThings 2025
---]]

local ModLoader = require 'asledgehammer/modloader/ModLoader';
local ZedCrypt = require 'asledgehammer/encryption/ZedCrypt';
require 'asledgehammer/network/LuaNetworkEvents';
require 'OptionScreens/MainScreen';

local mod = 'EtherHammerX';
local info = function(msg)
    print('[' .. mod .. '] :: ' .. msg);
end

local function lerp(start, stop, percent)
    return (start + percent * (stop - start));
end

(function()
    local logo = getTexture('media/ui/ehx_logo_transparent.png');
    local old_render = MainScreen.render;
    local old_onMouseDown = MainScreen.onMouseDown;

    local core = getCore();

    local function getLogoBoundary()
        local x1, y1 = core:getScreenWidth() - 256, 0;
        local x2, y2 = x1 + 256, 105;
        return x1, y1, x2, y2;
    end

    local inside_logo = 0;
    local logo_steps = 5;
    MainScreen.render = function(self)
        -- Call original method.
        old_render(self);

        local mx, my = getMouseX(), getMouseY();
        local alpha = 0.75;
        local lx1, ly1, lx2, ly2 = getLogoBoundary();
        if lx1 <= mx and mx <= lx2 and ly1 <= my and my <= ly2 then
            if inside_logo < logo_steps then
                inside_logo = logo_steps;
            end
        else
            if inside_logo > 0 then
                inside_logo = inside_logo - 1;
            end
        end

        if inside_logo ~= 0 then
            alpha = lerp(alpha, 1.0, (inside_logo / logo_steps));
        end

        -- Render our stuff.
        -- Logo:
        --   100%: 1024 x 420
        --    25%:  256 x 105
        self:drawTextureScaledUniform(logo, lx1, ly1, 0.25, alpha, 1, 1, 1);
    end

    MainScreen.onMouseDown = function(self, mx, my)
        -- Call original method.
        old_onMouseDown(self, mx, my);

        -- Check and see if the player clicked on the logo.
        local lx1, ly1, lx2, ly2 = getLogoBoundary();
        if lx1 <= mx and mx <= lx2 and ly1 <= my and my <= ly2 then
            openUrl('https://github.com/asledgehammer/EtherHammerX/');
        end
    end

    --- Protective padding for one-trigger self-removed functions.
    Events.OnLuaNetworkConnected.Add(function () end);
    Events.OnLuaNetworkConnected.Add(function()
        ModLoader.requestServerFile('EtherHammerX', 'client', function(result, data)
            if result == ModLoader.RESULT_FILE_NOT_FOUND then
                info('File not installed on server. The client will likely be kicked for not loading the anti-cheat.');
                return;
            end
            loadstring(ZedCrypt.decrypt(data, '__EtherHammerX__'))();
        end);
    end);
end)();
