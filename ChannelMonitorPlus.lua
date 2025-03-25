--[[ 
  ChannelMonitorPlus.lua
  A simple chat monitoring addon for WoW 1.12.1
  Tracks certain keywords in channel, say, or yell messages.
--]]

-- Make sure these are declared as globals (outside of any function):
ChannelMonitorPlus_x = ChannelMonitorPlus_x or 0
ChannelMonitorPlus_y = ChannelMonitorPlus_y or 0
ChannelMonitorPlus_dx = ChannelMonitorPlus_dx or 250
ChannelMonitorPlus_dy = ChannelMonitorPlus_dy or 120
ChannelMonitorPlus_on = ChannelMonitorPlus_on == nil and true or ChannelMonitorPlus_on
ChannelMonitorPlus_filter = ChannelMonitorPlus_filter or ''
ChannelMonitorPlus_ignore_filter = ChannelMonitorPlus_ignore_filter or ''
-- New global to store background opacity (range 0-1). Defaults to 0.45.
ChannelMonitorPlus_opacity = ChannelMonitorPlus_opacity or 0.45
-- New global to track whether audio is on (true) or off (false). Defaults to true.
ChannelMonitorPlus_audio = ChannelMonitorPlus_audio == nil and true or ChannelMonitorPlus_audio

-- Initialize the channels table if it doesn't exist
if not ChannelMonitorPlus_channels then
    ChannelMonitorPlus_channels = {
        SAY = true,
        YELL = true
        -- Channel entries will be added dynamically
    }
end

------------------------------------------------------
-- Global helper functions that persist through reloads
------------------------------------------------------
function CM_check_keyword(message, keyword)
    if strlen(keyword) > 0 then
        local position = 1
        while true do
            local start_pos, end_pos = strfind(strupper(message), strupper(keyword), position, true)
            if start_pos then
                local before_char = strsub(message, start_pos - 1, start_pos - 1)
                local after_char = strsub(message, end_pos + 1, end_pos + 1)
                -- Must not be alphanumeric on either side
                if (start_pos == 1 or not strfind(before_char, '%w'))
                   and (end_pos == strlen(message) or not strfind(after_char, '%w')) then
                    return true
                end
                position = end_pos + 1
            else
                break
            end
        end
    end
    return false
end

function CM_message_matches(message)
    -- Check for ignored keywords first
    for keyword in string.gfind(ChannelMonitorPlus_ignore_filter, '[^,]+') do
        keyword = gsub(keyword, '^%s*', '')
        keyword = gsub(keyword, '%s*$', '')
        if CM_check_keyword(message, keyword) then
            return false
        end
    end

    -- Then check positive keywords
    local open_bracket
    local condition
    for keyword in string.gfind(ChannelMonitorPlus_filter, '[^,]+') do
        keyword = gsub(keyword, '^%s*', '')
        keyword = gsub(keyword, '%s*$', '')

        if not open_bracket then
            condition = true
        end

        if strsub(keyword, 1, 1) == '(' then
            open_bracket = true
            keyword = gsub(keyword, '^%(%s*', '')
        end
        if strsub(keyword, -1, -1) == ')' then
            open_bracket = false
            keyword = strsub(keyword, 1, -2)
            keyword = gsub(keyword, '%)%s*$', '')
        end

        local negated
        if strsub(keyword, 1, 1) == '!' then
            negated = true
            keyword = gsub(keyword, '^!%s*', '')
        end

        local match = CM_check_keyword(message, keyword)
        if negated then
            match = not match
        end

        condition = condition and match
        if not open_bracket and condition then
            return true
        end
    end

    return false
end

------------------------------------------------------
-- Main addon table/frame
------------------------------------------------------
local channel_monitor = CreateFrame('Frame')
local channel_name_to_id_map = {}  -- Maps channel names to their internal IDs

-- For Vanilla: events call "this[event](this)" in OnEvent
channel_monitor:SetScript('OnEvent', function()
    local func = this[event]
    if func then
        func(this)
    end
end)

-- We'll always register ADDON_LOADED so slash commands can function
channel_monitor:RegisterEvent('ADDON_LOADED')
channel_monitor:RegisterEvent('PLAYER_ENTERING_WORLD')
channel_monitor:RegisterEvent('CHAT_MSG_CHANNEL_NOTICE')

------------------------------------------------------
-- Update channel list from server
------------------------------------------------------
function channel_monitor:update_channels()
    -- Clean up the channels table first - remove invalid entries 
    -- Keep only SAY, YELL, and numeric channel IDs
    local validChannels = {
        SAY = ChannelMonitorPlus_channels["SAY"],
        YELL = ChannelMonitorPlus_channels["YELL"]
    }
    
    -- Preserve numeric channel IDs
    for k, v in pairs(ChannelMonitorPlus_channels) do
        if tonumber(k) then
            validChannels[k] = v
        end
    end
    
    -- Replace the channels table with cleaned version
    ChannelMonitorPlus_channels = validChannels
    
    -- Update channel name-to-ID mapping (for correct message filtering)
    self:update_channel_name_map()
    
    -- Now update the UI
    if self.checkbox_container then
        self:update_channel_checkboxes()
    end
end

------------------------------------------------------
-- Save channel settings to persist between sessions
------------------------------------------------------
function channel_monitor:save_channel_settings()
    -- Force a variables write if available
    if SaveVariables then
        SaveVariables("ChannelMonitorPlus")
    end
end

------------------------------------------------------
-- Update channel checkboxes in the UI
------------------------------------------------------
function channel_monitor:update_channel_checkboxes()
    -- Clear existing checkboxes
    if self.checkbox_container.checkboxes then
        for _, checkbox in pairs(self.checkbox_container.checkboxes) do
            checkbox:Hide()
        end
    else
        self.checkbox_container.checkboxes = {}
    end
    
    -- Create Say and Yell checkboxes
    local position = 5
    local checkbox_width = 25  -- Reduced for tighter spacing
    
    -- Helper function to create a channel checkbox
    local function CreateChannelCheckbox(parent, name, label, tooltip)
        local existingCheckbox = self.checkbox_container.checkboxes[name]
        
        if not existingCheckbox then
            -- Create unique name for the checkbox
            local checkboxName = "ChannelMonitorPlusCheckbox_" .. name
            
            -- Create the checkbox with a proper name
            local checkbox = CreateFrame("CheckButton", checkboxName, parent, "UICheckButtonTemplate")
            checkbox:SetWidth(18)  -- Smaller size
            checkbox:SetHeight(18)
            checkbox:SetPoint("LEFT", position, 0)
            
            -- Modify the text object
            local textObj = getglobal(checkboxName .. "Text")
            if textObj then
                textObj:SetText(label)
                textObj:SetFontObject("GameFontNormalSmall")
                textObj:ClearAllPoints()
                textObj:SetPoint("LEFT", checkbox, "RIGHT", -2, 0)  -- Increased spacing
            end
            
            -- Set up tooltip
            checkbox:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltip)
                GameTooltip:Show()
            end)
            
            checkbox:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            
            -- Update saved variable when clicked - ALWAYS set value, never remove
            checkbox:SetScript("OnClick", function()
                -- Set to true or false, don't remove the entry
                ChannelMonitorPlus_channels[name] = (this:GetChecked() == 1)
                
                -- Special handling for World channel
                if string.find(tooltip, "World") then
                    -- When World checkbox is clicked, also update any linked internal IDs
                    for displayNum, internalID in pairs(self.display_to_internal or {}) do
                        if tostring(displayNum) == name then
                            ChannelMonitorPlus_channels[tostring(internalID)] = (this:GetChecked() == 1)
                        end
                    end
                end
                
                self:save_channel_settings()
            end)
            
            self.checkbox_container.checkboxes[name] = checkbox
        else
            -- Show existing checkbox
            existingCheckbox:Show()
            existingCheckbox:SetPoint("LEFT", position, 0)
            
            -- Update text
            local textObj = getglobal(existingCheckbox:GetName() .. "Text")
            if textObj then
                textObj:SetText(label)
            end
        end
        
        -- Initialize state from saved variable - default to true if not explicitly false
        local state = ChannelMonitorPlus_channels[name]
        if state == nil then
            state = true
            ChannelMonitorPlus_channels[name] = true
            
            -- Special handling for World channel
            if string.find(tooltip, "World") then
                -- Also initialize any linked internal IDs
                for displayNum, internalID in pairs(self.display_to_internal or {}) do
                    if tostring(displayNum) == name then
                        ChannelMonitorPlus_channels[tostring(internalID)] = true
                    end
                end
            end
        end
        
        self.checkbox_container.checkboxes[name]:SetChecked(state)
        
        position = position + checkbox_width
        return self.checkbox_container.checkboxes[name]
    end
    
    -- Create Say and Yell checkboxes
    CreateChannelCheckbox(self.checkbox_container, "SAY", "S", "Say")
    CreateChannelCheckbox(self.checkbox_container, "YELL", "Y", "Yell")
    
    -- Build a map of chat commands to channel names and IDs
    local commandToChannelName = {}
    local commandToChannelID = {}
    
    for i = 1, 9 do
        local id, name = GetChannelName(i)
        if id > 0 and name then
            -- Extract channel name without zone
            local baseName = name
            local dashPos = string.find(name, " - ")
            if dashPos then
                baseName = string.sub(name, 1, dashPos - 1)
            end
            
            commandToChannelName[i] = baseName
            commandToChannelID[i] = id
        end
    end
    
    -- For each channel in commandToChannelName, create a checkbox
    for chatCommand, channelName in pairs(commandToChannelName) do
        local internalID = commandToChannelID[chatCommand]
        
        -- Make sure we have the channel ID
        if internalID then
            -- Create the checkbox with chat command as label, channel name as tooltip
            CreateChannelCheckbox(
                self.checkbox_container,
                tostring(internalID),      -- Internal ID for the saved variable
                tostring(chatCommand),     -- Label is the chat command number
                channelName                -- Tooltip is the channel name
            )
        end
    end
end

------------------------------------------------------
-- Build a mapping of channel names to internal IDs
------------------------------------------------------
function channel_monitor:update_channel_name_map()
    -- Clear the existing map
    for k in pairs(channel_name_to_id_map) do
        channel_name_to_id_map[k] = nil
    end
    
    -- Track display number to internal ID mapping
    local display_to_internal = {}
    
    -- Get list of all channels
    local list = {GetChannelList()}
    local i = 1
    while list[i] do
        local internalID = list[i]
        local name = list[i+1]
        if internalID and name then
            -- Extract base name (remove zone info)
            local baseName = name
            local dashPos = string.find(name, " - ")
            if dashPos then
                baseName = string.sub(name, 1, dashPos - 1)
            end
            
            -- Extract display number if present
            local displayNum = nil
            local displayPattern = "^(%d+)%.%s*(.+)$"
            local _, _, num, channelName = string.find(name, displayPattern)
            if num and channelName then
                displayNum = tonumber(num)
                -- Store display number to internal ID mapping
                display_to_internal[displayNum] = internalID
                
                -- If this is a known channel (like World), ensure both display ID and internal ID are linked
                if channelName == "World" or string.find(channelName, "World") then
                    -- Link the checkbox states
                    if ChannelMonitorPlus_channels[tostring(displayNum)] ~= nil then
                        ChannelMonitorPlus_channels[tostring(internalID)] = ChannelMonitorPlus_channels[tostring(displayNum)]
                    elseif ChannelMonitorPlus_channels[tostring(internalID)] ~= nil then
                        ChannelMonitorPlus_channels[tostring(displayNum)] = ChannelMonitorPlus_channels[tostring(internalID)]
                    end
                end
            end
            
            -- Store both full name and base name
            channel_name_to_id_map[name] = internalID
            channel_name_to_id_map[baseName] = internalID
            
            -- Also store formats with channel number prefix (like "4. World")
            for j = 1, 9 do
                channel_name_to_id_map[j .. ". " .. baseName] = internalID
                channel_name_to_id_map[j .. "." .. baseName] = internalID
                channel_name_to_id_map[j .. " " .. baseName] = internalID
            end
        end
        i = i + 2
    end
    
    -- Store the display to internal ID mapping
    self.display_to_internal = display_to_internal
end

------------------------------------------------------
-- Show the message if it matches filters (with sound)
------------------------------------------------------
function channel_monitor:process_message(message, sender, language, channelName, target, flags, channelNumber, messageType)
    -- Check if channel is enabled in our filter
    local channel_enabled = false
    
    if messageType == "CHANNEL" then
        -- First try the direct channel number mapping
        channel_enabled = ChannelMonitorPlus_channels[tostring(channelNumber)] or false
        
        -- If not enabled but this is World channel (which has ID mismatch issue)
        if not channel_enabled and channelName and string.find(channelName, "World") then
            -- Try with the channel ID from our mapping
            local mappedID = channel_name_to_id_map["World"]
            if mappedID and ChannelMonitorPlus_channels[tostring(mappedID)] then
                channel_enabled = true
            end
            
            -- If World is enabled by display number, enable internal ID messages
            for displayNum, internalID in pairs(self.display_to_internal or {}) do
                if internalID == channelNumber and ChannelMonitorPlus_channels[tostring(displayNum)] then
                    channel_enabled = true
                    break
                end
            end
        end
    else
        -- For SAY, YELL
        channel_enabled = ChannelMonitorPlus_channels[messageType] or false
    end
    
    -- SIMPLIFIED FILTERING - Much more reliable 
    local matches_filter = false
    
    -- Check if we need to filter (if filter string is empty, all messages pass)
    if ChannelMonitorPlus_filter == "" then
        matches_filter = true
    else
        -- Check each keyword in the filter
        for keyword in string.gfind(ChannelMonitorPlus_filter, '[^,]+') do
            keyword = gsub(keyword, '^%s*', '')  -- Trim leading spaces
            keyword = gsub(keyword, '%s*$', '')  -- Trim trailing spaces
            
            if keyword ~= "" then
                local start_pos = string.find(strupper(message), strupper(keyword), 1, true)
                if start_pos then
                    local end_pos = start_pos + string.len(keyword) - 1
                    
                    -- Check word boundaries - character before and after must be non-alphanumeric
                    local before_ok = (start_pos == 1) or not strfind(strsub(message, start_pos - 1, start_pos - 1), "%w")
                    local after_ok = (end_pos == strlen(message)) or not strfind(strsub(message, end_pos + 1, end_pos + 1), "%w")
                    
                    if before_ok and after_ok then
                        matches_filter = true
                        break -- Found a match, no need to check other keywords
                    end
                end
            end
        end
    end
    
    -- Check ignore filter only if we found a match
    if matches_filter and ChannelMonitorPlus_ignore_filter ~= "" then
        for keyword in string.gfind(ChannelMonitorPlus_ignore_filter, '[^,]+') do
            keyword = gsub(keyword, '^%s*', '')  -- Trim leading spaces
            keyword = gsub(keyword, '%s*$', '')  -- Trim trailing spaces
            
            if keyword ~= "" then
                local start_pos = string.find(strupper(message), strupper(keyword), 1, true)
                if start_pos then
                    local end_pos = start_pos + string.len(keyword) - 1
                    
                    -- Check word boundaries - character before and after must be non-alphanumeric
                    local before_ok = (start_pos == 1) or not strfind(strsub(message, start_pos - 1, start_pos - 1), "%w")
                    local after_ok = (end_pos == strlen(message)) or not strfind(strsub(message, end_pos + 1, end_pos + 1), "%w")
                    
                    if before_ok and after_ok then
                        matches_filter = false
                        break -- Found a match in ignore filter
                    end
                end
            end
        end
    end
    
    -- Only proceed if addon is "on," the message matches filters, it's not our own text, and the channel is enabled
    if ChannelMonitorPlus_on and matches_filter and sender ~= UnitName('player') and channel_enabled then
        
        -- Escape '%' symbols so they don't break format strings
        message = gsub(message, "%%", "%%%%")

        -- Retrieve any special flag (AFK, DND, etc.)
        local flag = flags ~= '' and TEXT(getglobal('CHAT_FLAG_'..flags)) or ''

        -- Show language unless it's empty, "Universal," or default language
        local lang = ''
        if language ~= '' and language ~= 'Universal' and language ~= GetDefaultLanguage('player') then
            lang = '['..language..'] '
        end

        -- Timestamp in orange
        local timestamp = '|cffffa900'..date('%H:%M')..'|r '

        -- Determine message template
        local messageTemplate
        local channelNumText = ''
        if messageType == 'CHANNEL' then
            messageTemplate = getglobal('CHAT_CHANNEL_GET')
            
            -- Get a user-friendly channel number instead of internal ID
            local displayNumber = channelNumber
            
            -- Extract display number from channelName if possible
            if channelName then
                local _, _, num = string.find(channelName, "^(%d+)%.%s*")
                if num then
                    displayNumber = num
                end
            end
            
            -- Search for matching display number for this internal ID
            if self.display_to_internal then
                for dispNum, intID in pairs(self.display_to_internal) do
                    if intID == channelNumber then
                        displayNumber = dispNum
                        break
                    end
                end
            end
            
            channelNumText = '['..(displayNumber or '?')..'] '
        elseif messageType == 'SAY' then
            messageTemplate = getglobal('CHAT_SAY_GET')
        else
            messageTemplate = getglobal('CHAT_YELL_GET')
        end

        -- Build the final formatted line
        local body = timestamp .. channelNumText .. format(
            TEXT(messageTemplate)..lang..message,
            flag..'|Hplayer:'..sender..'|h['..sender..']|h'
        )

        -- Get color info for this chat message type
        local info = ChatTypeInfo[messageType]
        self.message_frame:AddMessage(body, info.r, info.g, info.b, info.id)

        -- Play a notification sound if audio is on
        if ChannelMonitorPlus_audio then
            -- "PVPENTERQUEUE" is recognized sound name in 1.12.1
            PlaySound("PVPENTERQUEUE")
        end
    end
end

------------------------------------------------------
-- Event hooks
------------------------------------------------------
function channel_monitor:PLAYER_ENTERING_WORLD()
    -- Update channels when player enters world
    self:update_channels()
end

function channel_monitor:CHAT_MSG_CHANNEL_NOTICE()
    -- Update channels when channel changes occur
    self:update_channels()
end

function channel_monitor:CHAT_MSG_CHANNEL()
    self:process_message(arg1, arg2, arg3, arg4, arg5, arg6, arg7, 'CHANNEL')
end

function channel_monitor:CHAT_MSG_SAY()
    self:process_message(arg1, arg2, arg3, arg4, arg5, arg6, arg7, 'SAY')
end

function channel_monitor:CHAT_MSG_YELL()
    self:process_message(arg1, arg2, arg3, arg4, arg5, arg6, arg7, 'YELL')
end

------------------------------------------------------
-- Save/restore position
------------------------------------------------------
function channel_monitor:save_frame()
    self.main_frame:StopMovingOrSizing()
    local x, y = self.main_frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    ChannelMonitorPlus_x = floor(x - ux + 0.5)
    ChannelMonitorPlus_y = floor(y - uy + 0.5)
    ChannelMonitorPlus_dx = self.main_frame:GetWidth()
    ChannelMonitorPlus_dy = self.main_frame:GetHeight()
end

------------------------------------------------------
-- Register/Unregister chat events
-- (Prevents crashing in certain zone loads when "off")
------------------------------------------------------
function channel_monitor:registerChatEvents()
    self:RegisterEvent('CHAT_MSG_CHANNEL')
    self:RegisterEvent('CHAT_MSG_SAY')
    self:RegisterEvent('CHAT_MSG_YELL')
end

function channel_monitor:unregisterChatEvents()
    self:UnregisterEvent('CHAT_MSG_CHANNEL')
    self:UnregisterEvent('CHAT_MSG_SAY')
    self:UnregisterEvent('CHAT_MSG_YELL')
end

------------------------------------------------------
-- ADDON_LOADED
------------------------------------------------------
function channel_monitor:ADDON_LOADED()
    if arg1 ~= 'ChannelMonitorPlus' then
        return
    end

    -- Set up slash commands
    SLASH_CHANNEL_MONITOR1, SLASH_CHANNEL_MONITOR2 = '/ChannelMonitorPlus', '/cmp'
    function SlashCmdList.CHANNEL_MONITOR(arg)
        local cmd, value = string.match(arg, "^(%S+)%s*(%S*)$")

        if cmd == "on" then
            ChannelMonitorPlus_on = true
            channel_monitor:registerChatEvents()
            channel_monitor.main_frame:Show()
            DEFAULT_CHAT_FRAME:AddMessage("Channel Monitor Plus ON")

        elseif cmd == "off" then
            ChannelMonitorPlus_on = false
            channel_monitor:unregisterChatEvents()
            channel_monitor.main_frame:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("Channel Monitor Plus OFF")

        elseif cmd == "audio" then
            -- Toggle audio
            ChannelMonitorPlus_audio = not ChannelMonitorPlus_audio
            DEFAULT_CHAT_FRAME:AddMessage("Channel Monitor Plus sound is now "..
              (ChannelMonitorPlus_audio and "ON" or "OFF"))

        elseif cmd == "opacity" then
            local newValue = tonumber(value)
            if newValue and newValue >= 1 and newValue <= 100 then
                ChannelMonitorPlus_opacity = newValue / 100
                channel_monitor.main_frame:SetBackdropColor(0, 0, 0, ChannelMonitorPlus_opacity)
                DEFAULT_CHAT_FRAME:AddMessage("Channel Monitor Plus opacity set to "..value.."%")
            else
                DEFAULT_CHAT_FRAME:AddMessage("Usage: /cmp opacity 1-100")
            end

        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "Usage: /cmp on | off | audio | opacity <1-100>"
            )
        end
    end

    -- Either register chat events if "on", or not if "off"
    if ChannelMonitorPlus_on then
        self:registerChatEvents()
    else
        self:unregisterChatEvents()
    end

    ------------------------------------------------------
    -- Try to use a frame defined in channel_monitor.xml
    ------------------------------------------------------
    local main_frame = ChannelMonitorPlusFrame
    if not main_frame then
        -- Fallback if XML not loaded
        main_frame = CreateFrame('Frame', "ChannelMonitorPlusFrame", UIParent)
    end
    self.main_frame = main_frame

    -- Restore position/size
    main_frame:ClearAllPoints()
    main_frame:SetPoint('CENTER', UIParent, 'CENTER', ChannelMonitorPlus_x, ChannelMonitorPlus_y)
    main_frame:SetWidth(ChannelMonitorPlus_dx)
    main_frame:SetHeight(ChannelMonitorPlus_dy)

    -- Apply a simple backdrop if we can
    if main_frame.SetBackdrop then
        main_frame:SetBackdrop({
            bgFile = [[Interface\ChatFrame\ChatFrameBackground]],
            tile = true,
            tileSize = 16,
        })
        main_frame:SetBackdropColor(0, 0, 0, ChannelMonitorPlus_opacity)
    end

    main_frame:SetMinResize(250, 120)
    main_frame:SetMaxResize(700, 360)
    main_frame:SetClampedToScreen(true)
    main_frame:SetToplevel(true)
    main_frame:SetMovable(true)
    main_frame:EnableMouse(true)
    main_frame:RegisterForDrag('LeftButton')
    main_frame:SetScript('OnDragStart', function()
        if IsAltKeyDown() then
            this:StartSizing("BOTTOMRIGHT")
        else
            this:StartMoving()
        end
    end)
    main_frame:SetScript('OnDragStop', function()
        self:save_frame()
    end)

    -- Positive filter editbox
    local editbox = CreateFrame('EditBox', nil, main_frame)
    main_frame.editbox = editbox
    editbox:SetPoint('TOP', 0, -2)
    editbox:SetPoint('LEFT', 2, 0)
    editbox:SetPoint('RIGHT', -2, 0)
    editbox:SetAutoFocus(false)
    editbox:SetTextInsets(0, 0, 3, 3)
    editbox:SetMaxLetters(512)
    editbox:SetHeight(19)
    editbox:SetFontObject(GameFontNormal)
    editbox:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8' })
    editbox:SetBackdropColor(1, 1, 1, .2)
    editbox:SetText(ChannelMonitorPlus_filter)
    editbox:SetScript('OnTextChanged', function()
        ChannelMonitorPlus_filter = this:GetText()
    end)
    editbox:SetScript('OnEditFocusLost', function()
        this:HighlightText(0, 0)
    end)
    editbox:SetScript('OnEscapePressed', function()
        this:ClearFocus()
    end)
    editbox:SetScript('OnEnterPressed', function()
        this:ClearFocus()
    end)

    -- Ignore filter editbox (in red)
    local ignorebox = CreateFrame('EditBox', nil, main_frame)
    main_frame.ignorebox = ignorebox
    ignorebox:SetPoint('TOPLEFT', editbox, 'BOTTOMLEFT', 0, -2)
    ignorebox:SetPoint('TOPRIGHT', editbox, 'BOTTOMRIGHT', 0, -2)
    ignorebox:SetHeight(19)
    ignorebox:SetAutoFocus(false)
    ignorebox:SetTextInsets(0, 0, 3, 3)
    ignorebox:SetMaxLetters(512)
    ignorebox:SetFontObject(GameFontNormal)
    ignorebox:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8' })
    ignorebox:SetBackdropColor(1, 1, 1, .2)
    ignorebox:SetTextColor(1, 0, 0, 1)
    ignorebox:SetText(ChannelMonitorPlus_ignore_filter)
    ignorebox:SetScript('OnTextChanged', function()
        ChannelMonitorPlus_ignore_filter = this:GetText()
    end)
    ignorebox:SetScript('OnEditFocusLost', function()
        this:HighlightText(0, 0)
    end)
    ignorebox:SetScript('OnEscapePressed', function()
        this:ClearFocus()
    end)
    ignorebox:SetScript('OnEnterPressed', function()
        this:ClearFocus()
    end)

    -- Create a container frame for checkboxes
    local checkbox_container = CreateFrame("Frame", nil, main_frame)
    checkbox_container:SetPoint("TOPLEFT", ignorebox, "BOTTOMLEFT", 0, -2)
    checkbox_container:SetPoint("TOPRIGHT", ignorebox, "BOTTOMRIGHT", 0, -2)
    checkbox_container:SetHeight(24)
    self.checkbox_container = checkbox_container

    -- Initialize checkbox container
    checkbox_container.checkboxes = {}

    -- Update channel checkboxes based on current channels
    self:update_channels()
    
    -- ScrollingMessageFrame to display filtered chat
    local message_frame = CreateFrame('ScrollingMessageFrame', nil, main_frame)
    main_frame.message_frame = message_frame
    message_frame:SetFontObject(GameFontNormal)
    message_frame:SetJustifyH('LEFT')
    message_frame:SetPoint('TOPLEFT', checkbox_container, 'BOTTOMLEFT', 0, -2)
    message_frame:SetPoint('BOTTOMRIGHT', main_frame, 'BOTTOMRIGHT', -2, 2)
    
    -- OnHyperlinkClick - Handles clicks on player names in chat messages
    message_frame:SetScript('OnHyperlinkClick', function()
        -- Extract link text and button used
        local linkText = arg1 or ""
        local button = arg3
        
        -- Extract player name from hyperlink
        local _, _, playerName = string.find(linkText, "player:([^|]+)")
        
        -- Right-click to invite player
        if playerName and button == "RightButton" then
            InviteByName(playerName)
        else
            -- Default behavior for left-clicks
            ChatFrame_OnHyperlinkShow(arg1, arg2, arg3)
        end
    end)
    
    message_frame:SetScript('OnHyperlinkLeave', ChatFrame_OnHyperlinkHide)
    message_frame:EnableMouseWheel(true)
    message_frame:SetScript('OnMouseWheel', function()
        if arg1 == 1 then
            this:ScrollUp()
        elseif arg1 == -1 then
            this:ScrollDown()
        end
    end)
    message_frame:SetTimeVisible(120)

    -- Hide the main frame if turned off
    if not ChannelMonitorPlus_on then
        main_frame:Hide()
    end

    self.message_frame = message_frame
end