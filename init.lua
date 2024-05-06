local wf = hs.window.filter
local cache_root = os.getenv("HOME") .. '/.cache/hammerspoon/'

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

local function get_opened_win(wid, bundle_id)
    local certain_win, certain_win_b = nil, nil
    local ws = get_all_windows()
    for _, win in pairs(ws) do
        local wid_ = get_win_wid(win)
        local bid_ = get_win_bid(win)
        if wid and wid_ == wid and bid_ == bundle_id then
            certain_win = win
            break
        end
        if not wid and bid_ == bundle_id then
            certain_win_b = win
        end
    end
    return certain_win or certain_win_b
end

local function get_all_saved_scene()
    if not hs.fs.attributes(cache_root) then
        return
    end
    local scenes = {}
    for f in hs.fs.dir(cache_root) do
        if f ~= '.' and f ~= '..' and f ~= '.DS_Store' then
            local path = cache_root .. f
            local attrs = hs.fs.attributes(path)
            if attrs.mode == "directory" then
                table.insert(scenes, f)
            end
        end
    end
    return scenes
end

local function make_cache_exist(scene)
    if not hs.fs.attributes(cache_root) then
        hs.fs.mkdir(cache_root)
    end
    local root = cache_root .. scene .. '/'
    if hs.fs.attributes(root) then
        os.execute("rm -rf " .. root)
    end
    hs.fs.mkdir(root)
end

local function get_cache_path(scene, screen_uuid)
    local root = cache_root .. scene .. '/'
    if not hs.fs.attributes(root) then
        return
    end
    local path = root .. string.format('snapshot_%s', screen_uuid)
    return path
end

local function save_to_cache(scene, screen_uuid, data)
    local path = get_cache_path(scene, screen_uuid)
    local f, err = io.open(path, 'w')
    if err then
        return false, err
    end
    f:write(data)
    f:close()
    return true
end

local function load_from_cache(scene, screen_uuid)
    local path = get_cache_path(scene, screen_uuid)
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

local function restore_win_from_shot(wid, bid, shot)
    local win = get_opened_win(wid, bid)
    if not win then
        if wid then
            local is_launched = hs.application.launchOrFocusByBundleID(bid)
            if is_launched then
                local ret, err = restore_win_from_shot(nil, bid, shot)
                return ret, err
            end
        end
        return false, 'window not opened'
    end

    local screen_uuid = get_win_screen_uuid(win)
    local target_screen = hs.screen.find(shot.screen_uuid)
    if not target_screen then
        return false, 'no target screen found'
    end

    -- Move the window to its original screen
    if target_screen and screen_uuid ~= shot.screen_uuid then
        win:moveToScreen(target_screen)
    end

    -- Restore window frame and fullscreen state
    if shot.is_full_screen then
        win:setFullScreen(true)
    else
        win:setFrame(hs.geometry.rect(shot.frame._x, shot.frame._y, shot.frame._w, shot.frame._h))
    end

    return true
end

local function confirm_scene_dialog(exist_scenes)
    local content = 'Please enter the name of the current scene (e.g., Office, Home, Café):'
    if #exist_scenes > 0 then
        local options = ''
        for k, scene in pairs(exist_scenes) do
            options = options .. k .. '. ' .. scene .. '\n'
        end
        content = content .. '\n OR \n'
        content = content .. 'Choose one of the following scenes you have recorded: \n'
        content = content .. options
    end

    local choice, input = hs.dialog.textPrompt(
        "Snapshot",
        content,
        "",
        "Confirm",
        "Cancel"
    )

    if choice == 'Cancel' or not input or input == '' then
        print('cancel or empty input ... ')
        return nil
    end

    local scene = exist_scenes[tonumber(input)] or input
    return scene
end


--- ========= Snapshot =========
--- Snapshot is a Hammerspoon spoon that records and restores all windows' information.
--- It can record all windows' information to a cache file and
--- restore all windows' information from the cache file, including restoring windows to their original positions ... etc.

local obj = {}
obj.__index = obj
obj.name = 'Snapshot'
obj.version = '1.0.1'
obj.author = ''
obj.homepage = ''
obj.license = 'MIT - https://opensource.org/licenses/MIT'

-- Create local port for IPC
local port = hs.ipc.localPort('snapshot', function(_, status, args)
    if status == 0 then
        args = args:sub(2)
    end
end)
print('[snapshot] ', port)

--- Snapshot:record_all_windows()
--- Method
--- Record all windows' information to cache file
---
--- Parameters:
---  * scene - The name of the scene to be recorded. Alternatively, set it to nil to prompt the user to input the scene name or choose an existing scene name. (optional)
---
--- Returns:
---  * None
function obj:record_all_windows(scene)

    if not scene then
        -- Get all the scenes that have been saved previously
        local exist_scenes = get_all_saved_scene()
        -- Ask the user to select the scene to restore
        scene = confirm_scene_dialog(exist_scenes)
    end
    if not scene then return end

    print('[snapshot] record_all_windows scene: ' .. scene)
    make_cache_exist(scene)

    local focus_bundle = hs.window.frontmostWindow():application():bundleID()

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
        local ret, err = save_to_cache(scene, screen_uuid, hs.inspect(shots))
        if ret then
            print('save_to_cache success >> scene', scene, 'screen_uid', screen_uuid)
        else
            print('save_to_cache fail >> scene', scene, 'screen_uid', screen_uuid, 'ERROR:', err)
        end
    end
end

--- Snapshot:restore_all_windows()
--- Method
--- Restore all windows' information from cache file
---
--- Parameters:
---  * scene - The name of the scene to be restore. Alternatively, set it to nil to prompt the user to input the scene name or choose an existing scene name. (optional)
---
--- Returns:
---  * None
function obj:restore_all_windows(scene)

    if not scene then
        -- Get all the scenes that have been saved previously
        local exist_scenes = get_all_saved_scene()
        -- Ask the user to select the scene to restore
        scene = confirm_scene_dialog(exist_scenes)
    end

    if not scene then return end

    if not hs.fs.attributes(cache_root .. scene) then
        print('[snapshot] scene not found: ' .. scene)
        return
    end

    print('[snapshot] restore_all_windows scene: ' .. scene)

    -- Get all current opened screens
    -- Try load the snapshot from cache file
    local snapshots = {}
    local screens = get_all_screens()
    for _, screen in ipairs(screens) do
        local screen_uuid = screen:getUUID()
        local shots, err = load_from_cache(scene, screen_uuid)
        if not shots then
            print('load_from_cache error >> screen_uid', screen_uuid, 'err', err)
        end
        snapshots[screen_uuid] = shots or {}
    end

    -- Restore windows based on the snapshots
    for screen_uuid, shots in pairs(snapshots) do
        for wid, shot in pairs(shots) do
            local bid = shot.bundle_id
            local ret, err = restore_win_from_shot(wid, bid, shot)
            if ret then
                print('restore_win_from_shot >> wid', wid, 'bid', bid)
            else
                print('restore_win_from_shot >> wid', wid, 'bid', bid, 'ERROR', err)
            end
        end
    end
end

return obj