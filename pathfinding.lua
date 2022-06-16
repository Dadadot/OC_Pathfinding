local robot = require("robot")
local component = require("component")
local geo = component.geolyzer
local nav = component.navigation
local offset = {}
local finish = {}
local start = {}
local map = {}
local pathing_map = {}
local dnt = false
local off = {}
    off[1] = {0, -1, 0}
    off[2] = {0, 0, -1}
    off[3] = {-1, 0, 0}
    off[4] = {1, 0, 0}
    off[5] = {0, 0, 1}
    off[6] = {0, 1, 0}

-- match robots perceived coordinates with 'true' ingame coordinates
local function coord_correction()
    io.write("Enter robot x, y and z coordinates (seperated by spaces): \n")
    local io_x, io_y, io_z = io.read("*n", "*n", "*n")
    local nav_x, nav_y, nav_z = nav.getPosition()
    local offset_x = nav_x - io_x
    local offset_y = nav_y - io_y
    local offset_z = nav_z - io_z
    offset = {offset_x, offset_y, offset_z}
end

-- all coordinates +1000 because fuck negatives coordinates
local function get_coord()
    local nav_x, nav_y, nav_z = nav.getPosition()
    local x = nav_x - offset[1] + 1000
    local y = nav_y - offset[2] + 1000
    local z = nav_z - offset[3] + 1000
    return {x, y, z}
end

-- stolen, rounds numbers
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- robot moving stuff
local function turn_it(robotDir, targetDir)
  if robotDir == 5.0 then
    if targetDir == 4.0 then
      robot.turnAround()
    elseif targetDir == 3.0 then
      robot.turnRight()
    else
      robot.turnLeft()
    end
  elseif robotDir == 4.0 then
    if targetDir == 5.0 then
      robot.turnAround()
    elseif targetDir == 3.0 then
      robot.turnLeft()
    else
      robot.turnRight()
    end
  elseif robotDir == 3.0 then
    if targetDir == 5.0 then
      robot.turnLeft()
    elseif targetDir == 4.0 then
      robot.turnRight()
    else
      robot.turnAround()
    end
  else
    if targetDir == 5.0 then
      robot.turnRight()
    elseif targetDir == 4.0 then
      robot.turnLeft()
    else
      robot.turnAround()
    end
  end
end

local function move_it(target_in)
    local target_x, target_y, target_z = target_in[1], target_in[2], target_in[3]
    local target_dir
    local r_dir = nav.getFacing()
    local r_coord = get_coord()
    if r_coord[1] == target_in[1] and r_coord[2] == target_in[2] and r_coord[3] == target_in[3] then
        return
    end
    if r_coord[2] > target_y then
        robot.down()
    elseif r_coord[2] < target_y then
        robot.up()
    else
        if r_coord[1] > target_x then target_dir = 4.0
        elseif r_coord[1] < target_x then target_dir = 5.0
        elseif r_coord[3] > target_z then target_dir = 2.0
        elseif r_coord[3] < target_z then target_dir = 3.0
        end
        if r_dir ~= target_dir then
            turn_it(r_dir, target_dir)
        end
        robot.forward()
    end
end

local function distance(self_in, target_in)
  local return_distance = math.abs(target_in[1] - self_in[1]) + math.abs(target_in[2] - self_in[2]) + math.abs(target_in[3] - self_in[3])
  return return_distance
end

-- helper function for cmap, writes map with coordinates, hardness and traversability
local function c_map_writer(scan_in, coords_in)
    local x_in, y_in, z_in = coords_in[1], coords_in[2], coords_in[3]
    local r_coords = get_coord()
    local x = r_coords[1] + x_in
    local y = r_coords[2] + y_in
    local z = r_coords[3] + z_in
    map[x] = map[x] or {}
    map[x][y] = map[x][y] or {}
    map[x][y][z] = map[x][y][z] or {}
    if map[x][y][z][1] then
        map[x][y][z][1] = (map[x][y][z][1] + scan_in) / 2
    else
        map[x][y][z][1] = scan_in
    end
    if map[x][y][z][1] < 0.15 then
        map[x][y][z][2] = 1
    else
        map[x][y][z][2] = 0
    end
end

-- create map of surrounding area and store it to pairs(map)
local function c_map_main()
    local depth_x, depth_z, depth_y = 3, 3, 3
    local start_x, start_z, start_y = -1, -1, -1
	local tmp_scan = geo.scan(start_y, start_z, start_y, depth_x, depth_z, depth_y)
    local scan_out = {}
        scan_out[1] = tmp_scan[5]
        scan_out[2] = tmp_scan[11]
        scan_out[3] = tmp_scan[13]
        scan_out[4] = tmp_scan[15]
        scan_out[5] = tmp_scan[17]
        scan_out[6] = tmp_scan[23]
    for i = 1, 6 do
        c_map_writer(scan_out[i], off[i])
    end
    c_map_writer(0, {0, 0, 0})
end

-- creates pathing_map (traversable map nodes), adds fcost, open/closed, traversable/not
local function update_pathing_map()
    local r_coord = get_coord()
    for x, _ in pairs(map) do
        for y, _ in pairs(map[x]) do
            for z, _ in pairs(map[x][y]) do
                pathing_map[x] = pathing_map[x] or {}
                pathing_map[x][y] = pathing_map[x][y] or {}
                pathing_map[x][y][z] = pathing_map[x][y][z] or {}
                if not pathing_map[x][y][z][1] then
                    pathing_map[x][y][z][1] = distance({x, y, z}, finish)
                end
                if not pathing_map[x][y][z][2] then
                    if map[x][y][z][2] == 1 then
                        pathing_map[x][y][z][2] = 1
                    else
                        pathing_map[x][y][z][2] = 0
                    end
                end
                if not pathing_map[x][y][z][3] then
                    pathing_map[x][y][z][3] = map[x][y][z][2]
                end
            end
        end
    end
    pathing_map[r_coord[1]][r_coord[2]][r_coord[3]][2] = 0
end

local function search_next(map_in)
    local distance_min = math.huge
    local candidates = {}
    for x, _ in pairs(map_in) do
        for y, _ in pairs(map_in[x]) do
            for z, _ in pairs(map_in[x][y]) do
                if distance_min >= map_in[x][y][z][1] and map_in[x][y][z][2] == 1 then
                    distance_min = map_in[x][y][z][1]
                    if not candidates[distance_min] then
                        candidates[distance_min] = {}
                    end
                    table.insert(candidates[distance_min], {x, y, z})
                end
            end
        end
    end
    local return_coords = candidates[distance_min][math.random(1, #candidates[distance_min])]
    return return_coords
end

-- most beautiful function
-- Searches tmp_map for target blocks with decreasing step count. Basically walkable path reversed.
local function search_path_helper(path_in, target_in, start_in, steps_in)
    local return_path = {}
    table.insert(return_path, target_in)
    steps_in = steps_in - 1
    while true do:
        for i = 1, #off do
            if steps_in == 0 then
                return return_path
            end
            local x = target_in[1] + off[i][1]
            local y = target_in[2] + off[i][2]
            local z = target_in[3] + off[i][3]
            if path_in[x][y][z][3] == steps_in then
                table.insert(return_path, {x, y, z})
                target_in = {x, y, z}
                steps_in = steps_in - 1
            end
        end
    end
end

-- Searches pathing_map for path to next node
-- search_path[x][y][z] [1]fcost, [2]open/close, [3]stepcount
local function search_path(target_in)
    local tmp_path = {}
    local r_coord = get_coord()
    -- fist instance of virtual_x/y/z is robot current location
    local virtual_x, virtual_y, virtual_z = r_coord[1], r_coord[2], r_coord[3]
    local final_step
    -- robots current is written into tmp_path
    tmp_path[r_coord[1]] = {}
    tmp_path[r_coord[1]][r_coord[2]] = {}
    tmp_path[r_coord[1]][r_coord[2]][r_coord[3]] = {}
    tmp_path[r_coord[1]][r_coord[2]][r_coord[3]][1] = math.huge
    tmp_path[r_coord[1]][r_coord[2]][r_coord[3]][2] = 0
    tmp_path[r_coord[1]][r_coord[2]][r_coord[3]][3] = 0
    while true do
        local virtual_current = tmp_path[virtual_x][virtual_y][virtual_z]
        if virtual_x == target_in[1] and virtual_y == target_in[2] and virtual_z == target_in[3] then
            break
        end
        virtual_current[2] = 0
        -- every adjacent cube to robot is validated(distance to tmp_target, open and stepcount) and added to tmp_path (if traversable)
        for i = 1, 6 do
            local x = virtual_x + off[i][1]
            local y = virtual_y + off[i][2]
            local z = virtual_z + off[i][3]
            if pathing_map[x][y][z] then
                if pathing_map[x][y][z][3] == 1 then
                    tmp_path[x] = tmp_path[x] or {}
                    tmp_path[x][y] = tmp_path[x][y] or {}
                    tmp_path[x][y][z] = tmp_path[x][y][z] or {}
                    if not tmp_path[x][y][z][1] then
                        tmp_path[x][y][z][1] = distance({x, y, z}, target_in)
                    end
                    if not tmp_path[x][y][z][2] then
                        tmp_path[x][y][z][2] = 1
                    end
                    if not tmp_path[x][y][z][3]
                        or tmp_path[x][y][z][3] > virtual_current[3] + 1 then
                            tmp_path[x][y][z][3] = virtual_current[3] + 1
                    end
                end
            end
        end
        local next_step = search_next(tmp_path)
        virtual_x, virtual_y, virtual_z = next_step[1], next_step[2], next_step[3]
    end
    final_step = tmp_path[target_in[1]][target_in[2]][target_in[3]][3]
    local return_path = search_path_helper(tmp_path, target_in, path_start, final_step)
    return return_path
end

local function walk_path(path_in)
    for i = #path_in, 1, -1 do
        move_it(path_in[i])
        c_map_main()
        update_pathing_map()
    end
end


local function main()
    coord_correction()
    start = get_coord()
    print("Enter target block x, y, z: \n")
    local t_x, t_y, t_z = io.read("*n", "*n", "*n")
    t_x = t_x + 1000
    t_y = t_y + 1000
    t_z = t_z + 1000

    finish[1], finish[2], finish[3] = t_x, t_y, t_z
    c_map_main()
    update_pathing_map()
    while true do
        local next, path
        next = search_next(pathing_map)
        path = search_path(next)
        walk_path(path)
        if next[1] == finish[1] and next[2] == finish[2] and next[3] == finish[3] then
            break
        end
    end
end

main()
-- g-cost = distance from start, h-cost = distance from finish, f-cost = g-cost + h-cost  (math.abs for positive)
-- clone map -> value nodes -> priority: shortest, shortest + closest, random shortest + closest
-- backwards search from target node to current node -> move
--[[
define start, finish
1 (c_map, c_pathing_map - robot current closed, adjacent nodes current node steps +1 if none or steps > current node steps + 1)
2 (search priority, open node pathing map)
create move_path
3 move (1 after every move until move_path empty)
2
3
until fin, reset pathing_map


-- map[x][y][z] [1] hardness [2] traversable/not traversable 1/0
-- pathing_map[x][y][z] [1] fCost [2] open/closed 1/0 [3] traversable/not 1/0
search_path: fcost, open/close, stepcount
--]]





-- todo:
-- if blocks change or if move fails (dunno)-> reset maps + reset pathfinding
-- scan 3x3x3 -> take adjacent nodes instead of 6 scans
-- functions taking tables as input
-- for x, for y, for z function?
-- remove map
