local wf = hs.window.filter

local function get_all_screens()
    return hs.screen.allScreens()
end

local function get_all_windows()
    local f = wf.new()
    local ws = f:getWindows()
    return ws
end

local function get_win_wid(win)
    return win:id()
end

local function get_win_bid(win)
    local p = win:application()
    return p and p:bundleID() or 'unknown'
end

local function get_win_screen_uuid(win)
    return win:screen():getUUID()
end

local function get_win_frame(win)
    return win:frame()
end

local function get_win_is_full_screen(win)
    return win:isFullScreen()
end

local function get_win_space_id(win)
    local ss = hs.spaces.windowSpaces(win) or {}
    return ss[1]
end

local function get_cache_path(screen_uuid)
    local root = os.getenv("HOME") .. '/.cache/hammerspoon/'
    if not hs.fs.attributes(root) then
        hs.fs.mkdir(root)
    end
    local path = root .. string.format('snapshot_%s', screen_uuid)
    return path
end

local function save_to_cache(screen_uuid, data)
    local path = get_cache_path(screen_uuid)
    local f, err = io.open(path, 'w')
    if err then
        return false, err
    end
    f:write(data)
    f:close()
    return true
end

local function load_from_cache(screen_uuid)
    local path = get_cache_path(screen_uuid)
    local f, err = io.open(path, 'r')
    if err then
        return nil, err
    end

    local ret = f:read('*a')
    f:close()

    local fn, err = load("return " .. ret)
    if err then
        return nil, err
    end

    local data = fn()
    return data
end


--- ========= Snapshot =========
--- Snapshot is a Hammerspoon spoon that records and restores all windows' information.
--- It can record all windows' information to a cache file and
--- restore all windows' information from the cache file, including restoring windows to their original positions ... etc.

local obj = {}
obj.__index = obj
obj.name = 'Snapshot'
obj.version = '1.0.0'
obj.author = ''
obj.homepage = ''
obj.license = 'MIT - https://opensource.org/licenses/MIT'

--- Snapshot:record_all_windows()
--- Method
--- Record all windows' information to cache file
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:record_all_windows()
    print('[snapshot] record_all_windows')

    local snapshots = {}
    local ws = get_all_windows()
    for _, win in pairs(ws) do
        local wid = get_win_wid(win)
        local screen_uuid = get_win_screen_uuid(win)

        local shots = snapshots[screen_uuid]
        if not shots then
            shots = {}
            snapshots[screen_uuid] = shots
        end

        shots[wid] = {
            bundle_id = get_win_bid(win),
            space_id = get_win_space_id(win),
            screen_uuid = get_win_screen_uuid(win),
            frame = get_win_frame(win),
            is_full_screen = get_win_is_full_screen(win),
        }
    end

    for screen_uuid, shots in pairs(snapshots) do
        local ret, err = save_to_cache(screen_uuid, hs.inspect(shots))
        if ret then
            print('save_to_cache success >> screen_uid', screen_uuid)
        else
            print('save_to_cache fail >> screen_uid', screen_uuid, 'err', err)
        end
    end
end

--- Snapshot:restore_all_windows()
--- Method
--- Restore all windows' information from cache file
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:restore_all_windows()
    print('[snapshot] restore_all_windows')

    local snapshots = {}
    local screens = get_all_screens()
    for _, screen in ipairs(screens) do
        local screen_uuid = screen:getUUID()
        local shots, err = load_from_cache(screen_uuid)
        if not shots then
            print('load_from_cache error >> screen_uid', screen_uuid, 'err', err)
        end
        snapshots[screen_uuid] = shots or {}
    end

    local ws = get_all_windows()
    for _, win in pairs(ws) do
        local wid = get_win_wid(win)
        local bid = get_win_bid(win)

        local wshot, bwshot = nil, nil
        for _, shots in pairs(snapshots or {}) do
            local shot = shots[wid]
            if shot and bid == shot.bundle_id then
                wshot = shot
                break
            end

            if not bwshot then
                for _, shot_ in pairs(shots) do
                    if bid == shot_.bundle_id then
                        bwshot = shot
                        break;
                    end
                end
            end
        end

        wshot = wshot or bwshot

        if wshot then
            local screen_uuid = get_win_screen_uuid(win)
            local target_screen = hs.screen.find(wshot.screen_uuid)
            if target_screen and screen_uuid ~= wshot.screen_uuid then
                win:moveToScreen(target_screen)
            end

            if wshot.is_full_screen then
                win:setFullScreen(true)
            else
                win:setFrame(hs.geometry.rect(wshot.frame._x, wshot.frame._y, wshot.frame._w, wshot.frame._h))
            end
        end
    end
end

return obj