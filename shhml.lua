_addon.name      = 'shhml';
_addon.author    = 'Dazusu';
_addon.version   = '1.0.0.0';
_addon.commands  = {'shhml'}
local addon_path = windower.addon_path:gsub('\\', '/')
local json = require("dkjson")
local spam = require("spam_detector")

local detector = spam:new({
    spam_threshold = 55,
    ml_model_path = addon_path .. "spam_model.lua",
});

packets = require('packets')

windower.register_event('incoming chunk', function(id,data)
    if id == 0x017 then
        local chat = packets.parse('incoming', data)
        if chat['Mode'] == 26 then
            local msg = windower.convert_auto_trans(chat['Message']):lower()
            local player = chat['Sender Name']

            local message_data = { player = player, full_message_string = msg }
            local is_spam, score, reasons = detector:check_message(message_data)
            if is_spam then
                return true
            end
        end
    end
end)
