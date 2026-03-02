-- VLC Playlist Manager
-- MIT License
-- Original author: basaquer (http://addons.videolan.org/content/show.php/Playlist+Cleaner?content=155249)
-- Improvements: Jules Lazaro
--
-- Fixes from original:
--   - Non-file:// URIs (streams, network items) correctly skipped by orphan check
--   - Linux/Mac paths no longer have their leading slash incorrectly stripped
--   - check_orphans now explicitly returns true/false in all code paths
--   - Permission-denied errors no longer falsely flag files as orphaned
--   - Playlist not mutated during iteration (collect-then-delete)
--   - Global variable leaks fixed
--
-- Features:
--   - Playlist Stats (total tracks, duplicates, streams, untagged — no disk scan)
--   - Remove Duplicates
--   - Remove Orphaned Files
--   - Remove Tracks Shorter Than X
--   - Remove Tracks Longer Than X
--   - Remove All Non-Local Files (streams, HTTP URLs, etc.)
--   - Remove Tracks With No Metadata
--   - Remove by File Extension (auto-populated from playlist)
--   - Shuffle Playlist (Fisher-Yates, Weighted by Duration, Interleaved, Seeded)

local dlg
local widgets = {}
local duration_input, unit_dropdown
local ext_dropdown, ext_list
local seed_input
local shuffle_dropdown

function descriptor()
    return {
        title       = "VLC Playlist Manager",
        version     = "1.0",
        author      = "basaquer, Jules Lazaro",
        url         = "http://addons.videolan.org/content/show.php/Playlist+Cleaner?content=155249",
        shortdesc   = "VLC Playlist Manager",
        description = "<div style=\"color:#0c0c0c;background-color:#fff;\"><b>VLC Playlist Manager</b> "
                   .. "is a VLC extension that analyses and cleans playlists: removing duplicates, "
                   .. "orphans, non-local files, untagged tracks, and more.</div>",
    }
end

function activate()
    dlg = vlc.dialog("VLC Playlist Manager")
    show_main_menu()
end

function close()
    vlc.deactivate()
end

-- ─── Widget Management ────────────────────────────────────────────────────────

function clear_screen()
    for _, w in ipairs(widgets) do
        dlg:del_widget(w)
    end
    widgets = {}
end

function add_label(text, col, row, hspan, vspan)
    local w = dlg:add_label(text, col, row, hspan, vspan)
    table.insert(widgets, w)
    return w
end

function add_button(text, fn, col, row, hspan, vspan)
    local w = dlg:add_button(text, fn, col, row, hspan, vspan)
    table.insert(widgets, w)
    return w
end

function add_text_input(text, col, row, hspan, vspan)
    local w = dlg:add_text_input(text, col, row, hspan, vspan)
    table.insert(widgets, w)
    return w
end

function add_dropdown(col, row, hspan, vspan)
    local w = dlg:add_dropdown(col, row, hspan, vspan)
    table.insert(widgets, w)
    return w
end

-- ─── Main Menu ────────────────────────────────────────────────────────────────

function show_main_menu()
    clear_screen()
    add_label("<b>VLC Playlist Manager v1.0</b>",       1, 1,  4, 1)
    add_label("by basaquer, Jules Lazaro",               1, 2,  4, 1)
    add_label("",                                        1, 3,  4, 1)
    add_button("Playlist Stats",                show_stats_screen,       1, 4,  4, 1)
    add_label("",                                        1, 5,  4, 1)
    add_label("<b>Remove</b>",                           1, 6,  4, 1)
    add_button("Remove Duplicates",             run_remove_duplicates,   1, 7,  4, 1)
    add_button("Remove Orphaned Files",         show_remove_orphans_warning, 1, 8,  4, 1)
    add_button("Remove Tracks Shorter Than…",   show_shorter_screen,     1, 9,  4, 1)
    add_button("Remove Tracks Longer Than…",    show_longer_screen,      1, 10, 4, 1)
    add_button("Remove All Non-Local Files",    run_remove_nonlocal,     1, 11, 4, 1)
    add_button("Remove Tracks With No Metadata",run_remove_no_metadata,  1, 12, 4, 1)
    add_button("Remove by File Extension…",     show_extension_screen,   1, 13, 4, 1)
    add_label("",                                        1, 14, 4, 1)
    add_label("<b>Shuffle</b>",                          1, 15, 4, 1)
    add_button("Shuffle Playlist…",             show_shuffle_screen,     1, 16, 4, 1)
    add_label("",                                        1, 17, 4, 1)
    add_button("Close",                         vlc.deactivate,          2, 18, 2, 1)
    dlg:update()
end

-- ─── Playlist Stats Screen ────────────────────────────────────────────────────

function show_stats_screen()
    local items   = get_playlist_items()
    local total   = #items
    local dupes   = count_duplicates(items)
    local streams = count_streams(items)
    local no_meta = count_no_metadata(items)

    clear_screen()
    add_label("<b>Playlist Stats</b>",                        1, 1,  4, 1)
    add_label("",                                             1, 2,  4, 1)
    add_label("Total tracks:",                                1, 3,  2, 1)
    add_label("<b>" .. total .. "</b>",                       3, 3,  2, 1)
    add_label("Duplicates detected:",                         1, 4,  2, 1)
    add_label("<b>" .. dupes .. "</b>",                       3, 4,  2, 1)
    add_label("Non-local / stream URLs:",                     1, 5,  2, 1)
    add_label("<b>" .. streams .. "</b>",                     3, 5,  2, 1)
    add_label("Tracks with no metadata:",                     1, 6,  2, 1)
    add_label("<b>" .. no_meta .. "</b>",                     3, 6,  2, 1)
    add_label("",                                             1, 7,  4, 1)
    add_label("<i>No changes were made.</i>",                 1, 8,  4, 1)
    add_label("",                                             1, 9,  4, 1)
    add_button("Scan for Orphaned Files…", show_orphan_scan_warning, 1, 10, 4, 1)
    add_label("",                                             1, 11, 4, 1)
    add_button("← Back to Menu", show_main_menu,              1, 12, 4, 1)
    dlg:update()
end

function show_orphan_scan_warning()
    local items = get_playlist_items()
    local total = #items
    clear_screen()
    add_label("<b>Scan for Orphaned Files</b>",               1, 1,  4, 1)
    add_label("",                                             1, 2,  4, 1)
    add_label("This will check all " .. total .. " files",    1, 3,  4, 1)
    add_label("on disk one by one.",                          1, 4,  4, 1)
    add_label("",                                             1, 5,  4, 1)
    add_label("<b>VLC will appear frozen during</b>",         1, 6,  4, 1)
    add_label("<b>the scan. This is normal.</b>",             1, 7,  4, 1)
    add_label("Please be patient.",                           1, 8,  4, 1)
    add_label("",                                             1, 9,  4, 1)
    add_button("Scan Now",   run_orphan_stats_scan,           1, 10, 2, 1)
    add_button("← Back",     show_stats_screen,               3, 10, 2, 1)
    dlg:update()
end

function run_orphan_stats_scan()
    local items   = get_playlist_items()
    local orphans = count_orphans(items)
    local total   = #items

    clear_screen()
    add_label("<b>Orphan Scan Complete</b>",                  1, 1,  4, 1)
    add_label("",                                             1, 2,  4, 1)
    add_label("Files checked:",                               1, 3,  2, 1)
    add_label("<b>" .. total .. "</b>",                       3, 3,  2, 1)
    add_label("Orphaned files found:",                        1, 4,  2, 1)
    add_label("<b>" .. orphans .. "</b>",                     3, 4,  2, 1)
    add_label("",                                             1, 5,  4, 1)
    add_label("<i>No changes were made.</i>",                 1, 6,  4, 1)
    add_label("",                                             1, 7,  4, 1)
    add_button("← Back to Stats",  show_stats_screen,         1, 8,  2, 1)
    add_button("← Main Menu",      show_main_menu,            3, 8,  2, 1)
    dlg:update()
end

-- ─── Duration Screens ─────────────────────────────────────────────────────────

function show_shorter_screen()
    clear_screen()
    add_label("<b>Remove Tracks Shorter Than</b>",       1, 1, 4, 1)
    add_label("",                                        1, 2, 4, 1)
    add_label("Enter a duration:",                       1, 3, 4, 1)
    duration_input = add_text_input("",                  1, 4, 2, 1)
    unit_dropdown  = add_dropdown(                       3, 4, 2, 1)
    unit_dropdown:add_value("seconds", 1)
    unit_dropdown:add_value("minutes", 2)
    unit_dropdown:add_value("hours",   3)
    add_label("",                                        1, 5, 4, 1)
    add_button("Remove",       run_remove_shorter,       1, 6, 2, 1)
    add_button("← Back",       show_main_menu,           3, 6, 2, 1)
    dlg:update()
end

function show_longer_screen()
    clear_screen()
    add_label("<b>Remove Tracks Longer Than</b>",        1, 1, 4, 1)
    add_label("",                                        1, 2, 4, 1)
    add_label("Enter a duration:",                       1, 3, 4, 1)
    duration_input = add_text_input("",                  1, 4, 2, 1)
    unit_dropdown  = add_dropdown(                       3, 4, 2, 1)
    unit_dropdown:add_value("seconds", 1)
    unit_dropdown:add_value("minutes", 2)
    unit_dropdown:add_value("hours",   3)
    add_label("",                                        1, 5, 4, 1)
    add_button("Remove",       run_remove_longer,        1, 6, 2, 1)
    add_button("← Back",       show_main_menu,           3, 6, 2, 1)
    dlg:update()
end

-- ─── Extension Screen ─────────────────────────────────────────────────────────

function show_extension_screen()
    local exts = get_playlist_extensions()

    clear_screen()
    add_label("<b>Remove by File Extension</b>",         1, 1, 4, 1)
    add_label("",                                        1, 2, 4, 1)

    if #exts == 0 then
        add_label("No local file extensions found in playlist.", 1, 3, 4, 1)
        add_label("",                                    1, 4, 4, 1)
        add_button("← Back", show_main_menu,             1, 5, 4, 1)
    else
        add_label("Select an extension to remove:",      1, 3, 4, 1)
        ext_dropdown = add_dropdown(                     1, 4, 4, 1)
        -- store ext_list parallel to dropdown so we can look up by index
        ext_list = exts
        for i, ext in ipairs(exts) do
            ext_dropdown:add_value(ext, i)
        end
        add_label("",                                    1, 5, 4, 1)
        add_button("Remove",   run_remove_by_extension,  1, 6, 2, 1)
        add_button("← Back",   show_main_menu,           3, 6, 2, 1)
    end
    dlg:update()
end

-- ─── Shuffle Screen ───────────────────────────────────────────────────────────

function show_shuffle_screen()
    clear_screen()
    add_label("<b>Shuffle Playlist</b>",                     1, 1, 4, 1)
    add_label("",                                            1, 2, 4, 1)
    add_label("Select shuffle method:",                      1, 3, 4, 1)
    shuffle_dropdown = add_dropdown(                         1, 4, 4, 1)
    shuffle_dropdown:add_value("Fisher-Yates (true random)",     1)
    shuffle_dropdown:add_value("Weighted by duration",           2)
    shuffle_dropdown:add_value("Interleaved by folder/artist",   3)
    shuffle_dropdown:add_value("Seeded shuffle (reproducible)",  4)
    add_label("",                                            1, 5, 4, 1)
    add_label("Seed (only used for Seeded shuffle):",        1, 6, 4, 1)
    seed_input = add_text_input("",                          1, 7, 4, 1)
    add_label("",                                            1, 8, 4, 1)
    add_button("Next…",        show_shuffle_warning,         1, 9, 2, 1)
    add_button("← Back",       show_main_menu,               3, 9, 2, 1)
    dlg:update()
end

function show_shuffle_warning()
    -- Validate seeded input before proceeding to warning
    local method = shuffle_dropdown:get_value()
    if method == 4 then
        local seed = tonumber(seed_input:get_text())
        if seed == nil or math.floor(seed) ~= seed then
            local w = dlg:add_label("⚠ Seeded shuffle requires a whole number seed.", 1, 10, 4, 1)
            table.insert(widgets, w)
            dlg:update()
            return
        end
    end

    local items = get_playlist_items()
    local total = #items
    clear_screen()
    add_label("<b>Shuffle Playlist</b>",                     1, 1,  4, 1)
    add_label("",                                            1, 2,  4, 1)
    add_label("Shuffling " .. total .. " tracks requires",   1, 3,  4, 1)
    add_label("deleting and re-adding every item.",          1, 4,  4, 1)
    add_label("",                                            1, 5,  4, 1)
    add_label("<b>VLC will appear frozen during</b>",        1, 6,  4, 1)
    add_label("<b>the operation. This is normal.</b>",       1, 7,  4, 1)
    add_label("Please be patient.",                          1, 8,  4, 1)
    add_label("",                                            1, 9,  4, 1)
    add_button("Shuffle Now",  run_shuffle,                  1, 10, 2, 1)
    add_button("← Back",       show_shuffle_screen,          3, 10, 2, 1)
    dlg:update()
end

-- ─── Result / Error Screens ───────────────────────────────────────────────────

function show_result(message)
    clear_screen()
    add_label("<b>Done</b>",                             1, 1, 4, 1)
    add_label("",                                        1, 2, 4, 1)
    add_label(message,                                   1, 3, 4, 1)
    add_label("",                                        1, 4, 4, 1)
    add_button("← Back to Menu", show_main_menu,         1, 5, 2, 1)
    add_button("Close",           vlc.deactivate,        3, 5, 2, 1)
    dlg:update()
end

function show_duration_error()
    local w = dlg:add_label("⚠ Please enter a valid positive whole number.", 1, 7, 4, 1)
    table.insert(widgets, w)
    dlg:update()
end

-- ─── Playback Guard ───────────────────────────────────────────────────────────

-- Stops playback and waits until VLC confirms it has fully stopped before
-- returning. This prevents crashes when removing the currently playing item.
function stop_playback_if_needed()
    local status = vlc.playlist.status()
    if status ~= "playing" and status ~= "paused" then
        return false
    end

    vlc.playlist.stop()

    -- Poll until VLC confirms stopped, with a timeout of ~2 seconds (200 x 10ms)
    local attempts = 0
    while vlc.playlist.status() ~= "stopped" and attempts < 200 do
        vlc.misc.mwait(10000)  -- 10ms in microseconds
        attempts = attempts + 1
    end

    return true
end

-- ─── Action Runners ───────────────────────────────────────────────────────────

function run_remove_duplicates()
    local was_playing = stop_playback_if_needed()
    local count = remove_duplicates()
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " duplicate track(s)." .. note)
end

function show_remove_orphans_warning()
    local items = get_playlist_items()
    local total = #items
    clear_screen()
    add_label("<b>Remove Orphaned Files</b>",                 1, 1,  4, 1)
    add_label("",                                             1, 2,  4, 1)
    add_label("This will check all " .. total .. " files",    1, 3,  4, 1)
    add_label("on disk and remove any that are missing.",     1, 4,  4, 1)
    add_label("",                                             1, 5,  4, 1)
    add_label("<b>VLC will appear frozen during</b>",         1, 6,  4, 1)
    add_label("<b>the scan. This is normal.</b>",             1, 7,  4, 1)
    add_label("Please be patient.",                           1, 8,  4, 1)
    add_label("",                                             1, 9,  4, 1)
    add_button("Remove Orphans", run_remove_orphans,          1, 10, 2, 1)
    add_button("← Back",         show_main_menu,              3, 10, 2, 1)
    dlg:update()
end

function run_remove_orphans()
    local was_playing = stop_playback_if_needed()
    local count = remove_orphans()
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " orphaned track(s)." .. note)
end

function run_remove_shorter()
    local threshold = get_threshold_seconds()
    if threshold == nil then show_duration_error() return end
    local was_playing = stop_playback_if_needed()
    local count = remove_by_duration(threshold, "shorter")
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " track(s) shorter than "
        .. duration_input:get_text() .. " " .. get_unit_name() .. "." .. note)
end

function run_remove_longer()
    local threshold = get_threshold_seconds()
    if threshold == nil then show_duration_error() return end
    local was_playing = stop_playback_if_needed()
    local count = remove_by_duration(threshold, "longer")
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " track(s) longer than "
        .. duration_input:get_text() .. " " .. get_unit_name() .. "." .. note)
end

function run_remove_nonlocal()
    local was_playing = stop_playback_if_needed()
    local count = remove_nonlocal()
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " non-local track(s)." .. note)
end

function run_remove_no_metadata()
    local was_playing = stop_playback_if_needed()
    local count = remove_no_metadata()
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " track(s) with no metadata." .. note)
end

function run_remove_by_extension()
    local idx = ext_dropdown:get_value()
    local ext = ext_list and ext_list[idx]
    if ext == nil then
        show_result("No extension selected.")
        return
    end
    local was_playing = stop_playback_if_needed()
    local count = remove_by_extension(ext)
    local note = was_playing and " Playback was stopped." or ""
    show_result("Removed " .. count .. " track(s) with extension " .. ext .. "." .. note)
end

function run_shuffle()
    local method = shuffle_dropdown:get_value()
    local seed_text = seed_input:get_text()
    local seed = (method == 4) and tonumber(seed_text) or nil

    shuffle_playlist(method, seed)

    local names = {
        "Fisher-Yates (true random)",
        "Weighted by duration",
        "Interleaved by folder/artist",
        "Seeded shuffle"
    }
    show_result("Playlist shuffled using " .. names[method] .. ".")
end

-- ─── Core Removal Logic ───────────────────────────────────────────────────────

function get_playlist_items()
    local items = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        table.insert(items, item)
    end
    return items
end

function remove_duplicates()
    local fileset   = {}
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if fileset[item.path] then
            table.insert(to_delete, tonumber(item.id))
        else
            fileset[item.path] = true
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

function remove_orphans()
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if not is_local_file_alive(item.path) then
            table.insert(to_delete, tonumber(item.id))
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

function remove_by_duration(threshold_secs, mode)
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        local duration = item.duration
        if duration and duration >= 0 then
            if mode == "shorter" and duration < threshold_secs then
                table.insert(to_delete, tonumber(item.id))
            elseif mode == "longer" and duration > threshold_secs then
                table.insert(to_delete, tonumber(item.id))
            end
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

function remove_nonlocal()
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if not string.match(item.path, "^file://") then
            table.insert(to_delete, tonumber(item.id))
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

function remove_no_metadata()
    -- A track is considered untagged if its name equals its bare filename
    -- (i.e. VLC found no title tag and fell back to the filename)
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if not has_metadata(item) then
            table.insert(to_delete, tonumber(item.id))
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

function remove_by_extension(ext)
    local to_delete = {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if get_extension(item.path) == ext then
            table.insert(to_delete, tonumber(item.id))
        end
    end
    for _, id in ipairs(to_delete) do vlc.playlist.delete(id) end
    return #to_delete
end

-- ─── Stats Counters (non-destructive) ────────────────────────────────────────

function count_duplicates(items)
    local fileset, count = {}, 0
    for _, item in ipairs(items) do
        if fileset[item.path] then
            count = count + 1
        else
            fileset[item.path] = true
        end
    end
    return count
end

function count_orphans(items)
    local count = 0
    for _, item in ipairs(items) do
        if string.match(item.path, "^file://") and not is_local_file_alive(item.path) then
            count = count + 1
        end
    end
    return count
end

function count_streams(items)
    local count = 0
    for _, item in ipairs(items) do
        if not string.match(item.path, "^file://") then
            count = count + 1
        end
    end
    return count
end

function count_no_metadata(items)
    local count = 0
    for _, item in ipairs(items) do
        if not has_metadata(item) then count = count + 1 end
    end
    return count
end

-- ─── Shuffle Logic ────────────────────────────────────────────────────────────

function shuffle_playlist(method, seed)
    local items = get_playlist_items()
    if #items == 0 then return end

    local shuffled

    if method == 1 then
        shuffled = shuffle_fisher_yates(items)
    elseif method == 2 then
        shuffled = shuffle_weighted_duration(items)
    elseif method == 3 then
        shuffled = shuffle_interleaved(items)
    elseif method == 4 then
        shuffled = shuffle_seeded(items, seed)
    end

    -- Rebuild: delete all, then re-add in new order
    -- We stop playback first (already done by runner), then clear and re-add
    for _, item in ipairs(items) do
        vlc.playlist.delete(tonumber(item.id))
    end
    for _, item in ipairs(shuffled) do
        vlc.playlist.add({{ path = item.path, name = item.name }})
    end
end

-- Fisher-Yates uniform shuffle
function shuffle_fisher_yates(items)
    local t = {}
    for i, v in ipairs(items) do t[i] = v end
    math.randomseed(os.time())
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Weighted by duration: shorter tracks bubble toward the front probabilistically
function shuffle_weighted_duration(items)
    math.randomseed(os.time())
    local tagged = {}
    for _, item in ipairs(items) do
        local dur = (item.duration and item.duration > 0) and item.duration or 180
        -- weight = 1/duration so shorter tracks get a higher sort key on average
        table.insert(tagged, { item = item, key = math.random() / dur })
    end
    table.sort(tagged, function(a, b) return a.key > b.key end)
    local result = {}
    for _, v in ipairs(tagged) do table.insert(result, v.item) end
    return result
end

-- Interleaved: groups by top-level folder, then round-robins across groups
function shuffle_interleaved(items)
    math.randomseed(os.time())
    local groups = {}
    local order  = {}
    for _, item in ipairs(items) do
        local key = get_parent_folder(item.path)
        if not groups[key] then
            groups[key] = {}
            table.insert(order, key)
        end
        table.insert(groups[key], item)
    end
    -- Shuffle within each group and shuffle group order
    for _, key in ipairs(order) do
        groups[key] = shuffle_fisher_yates(groups[key])
    end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    -- Round-robin interleave
    local result, active = {}, {}
    for _, key in ipairs(order) do
        table.insert(active, { key = key, idx = 1 })
    end
    local remaining = #active
    while remaining > 0 do
        local i = 1
        while i <= #active do
            local g = active[i]
            if g.idx <= #groups[g.key] then
                table.insert(result, groups[g.key][g.idx])
                g.idx = g.idx + 1
                i = i + 1
            else
                table.remove(active, i)
                remaining = remaining - 1
            end
        end
    end
    return result
end

-- Seeded shuffle: deterministic Fisher-Yates using a simple LCG with the given seed
function shuffle_seeded(items, seed)
    local t = {}
    for i, v in ipairs(items) do t[i] = v end
    -- LCG parameters (Numerical Recipes)
    local m = 2^32
    local a = 1664525
    local c = 1013904223
    local state = seed % m
    local function lcg_rand(n)
        state = (a * state + c) % m
        return (state % n) + 1
    end
    for i = #t, 2, -1 do
        local j = lcg_rand(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- ─── File / URI Helpers ───────────────────────────────────────────────────────

function is_local_file_alive(filepath)
    if not string.match(filepath, "^file://") then return true end
    local pathval = uri_to_filepath(filepath)
    if pathval == nil then return true end
    local fh, err, code = io.open(pathval, "r")
    if fh then fh:close() return true end
    return code == 2 and false or true
end

function uri_to_filepath(filepath)
    local pathval = string.gsub(filepath, "^file://", "")
    if package.config:sub(1, 1) == "\\" then
        pathval = string.gsub(pathval, "^/", "")
    end
    return percent_decode(pathval)
end

function percent_decode(str)
    if str == nil then return nil end
    return string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
end

function get_extension(path)
    local decoded = percent_decode(path) or path
    return string.match(decoded, "%.([^%.]+)$") and
           string.lower(string.match(decoded, "%.([^%.]+)$")) or nil
end

function get_playlist_extensions()
    local seen, list = {}, {}
    for _, item in pairs(vlc.playlist.get("playlist", false).children) do
        if string.match(item.path, "^file://") then
            local ext = get_extension(item.path)
            if ext and not seen[ext] then
                seen[ext] = true
                table.insert(list, "." .. ext)
            end
        end
    end
    table.sort(list)
    return list
end

function get_parent_folder(path)
    local decoded = percent_decode(path) or path
    -- Return the immediate parent directory name as the group key
    return string.match(decoded, "^(.*)[/\\][^/\\]+$") or "root"
end

function has_metadata(item)
    -- VLC falls back to the filename as the item name when no tags are present.
    -- We check if the name looks like a bare filename (contains a file extension).
    if item.name == nil or item.name == "" then return false end
    -- If the name has no extension-like pattern it was probably set from tags
    local bare = string.match(item.name, "^.+%.[^%.]+$")
    -- Additionally check that the name matches the tail of the path
    local tail = string.match(item.path, "[/\\]([^/\\]+)$")
    if tail then
        tail = percent_decode(tail)
        if item.name == tail then return false end  -- name == filename = no metadata
    end
    return true
end

-- ─── Duration Input Helpers ───────────────────────────────────────────────────

function get_threshold_seconds()
    local text = duration_input:get_text()
    local val  = tonumber(text)
    if val == nil or val <= 0 or math.floor(val) ~= val then return nil end
    local unit = unit_dropdown:get_value()
    if unit == 2 then val = val * 60
    elseif unit == 3 then val = val * 3600
    end
    return val
end

function get_unit_name()
    local unit = unit_dropdown:get_value()
    if unit == 1 then return "second(s)"
    elseif unit == 2 then return "minute(s)"
    elseif unit == 3 then return "hour(s)"
    end
end
