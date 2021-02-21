------------
-- CONFIG --
------------
gui.defaultPixelFont("fceux") -- set default font
local SCREEN_WIDTH = 800 -- right side of screen (default 800)
local CHAR_WIDTH = 6 -- size of each individual character drawn on screen

local DO_DRAW_TIMER = true -- draw current level timer true/false
local DO_DRAW_LARA_INFO = true -- draw lara's position, speed, angle, health true/false
local DO_DRAW_MINIMAP = true -- draw minimap of the current room
local DO_DRAW_ITEM_MINI_INFO = true -- draw active entity info
local DO_DRAW_MOVIE_INFO = true -- draw current movie info
local DO_DRAW_ROOM_INFO = true -- draw Lara's current room info, position, top, bottom, etc

-- where to draw various things
local DRAW_TIMER_INFO_X = 0
local DRAW_TIMER_INFO_Y = 110
local DRAW_LARA_INFO_X = 0
local DRAW_LARA_INFO_Y = 140
local DRAW_MOVIE_INFO_X = 0
local DRAW_MOVIE_INFO_Y = 65
local DRAW_ENTITY_INFO_Y = 120
local DRAW_ENTITY_INFO_IGNORE_NON_INTELLIGENT = true -- when true, ignore non-intelligent entities
local DRAW_ROOM_INFO_X = 0
local DRAW_ROOM_INFO_Y = 200
local DRAW_MAP_X = 0
local DRAW_MAP_Y = 230

local DRAW_MAP_SCALE = 11 -- how many pixels each square in the minimap is (default 11x11)
local DRAW_MAP_COLOUR_DOOR = 0xFF222222
local DRAW_MAP_COLOUR_DEFAULT = 0xFF00FFFF
local DRAW_MAP_COLOUR_WALL = 0xFF808080
local DRAW_MAP_COLOUR_BACKGROUND = 0xFF000000
local DRAW_MAP_COLOUR_HOVER = 0xFF805E5E
local DRAW_MAP_COLOUR_TRIGGER = 0xFFFF00FF
local DRAW_MAP_COLOUR_LARA = 0xFF6A0DAD
local DRAW_MAP_COLOUR_ENEMY = 0xFFCC3311
local DRAW_MAP_ARROWHEAD_SIZE = 5

---------------
-- SHORTCUTS --
---------------
local u8 = memory.read_u8
local u16 = memory.read_u16_le
local u32 = memory.read_u32_le
local s8 = memory.read_s8
local s16 = memory.read_s16_le
local s32 = memory.read_s32_le

-------------------
-- GAME SPECIFIC --
-------------------
-- These are variables used for the script that vary based on the game being played.
local hash = gameinfo.getromhash()
local data = require 'game' 
local all_names = require 'names'

if data [hash] == nil then 
  error ( string.format ( 'Game unsupported! (hash 0x%s)', hash ) )
end 

local game = data [hash]
local names = all_names[game["name"]]

for k,v in pairs(names) do print(k,v) end

local ram = game.ram -- memory addresses
local SECTOR_PIXELS = game.sector_pixels
local STRUCT_LEN_SECTOR = game.struct_len_sector -- how many bytes each sector data is
local STRUCT_LEN_ROOM = game.struct_len_room -- how many bytes each room is
local STRUCT_LEN_ENTITY = game.struct_len_entity -- how many bytes each entity is

---------------
-- CONSTANTS --
---------------
local BIT_FLOOR_DATA_DOOR = 0x1 -- floor data function for portal
local BIT_FLOOR_DATA_FLOOR_SLANT = 0x2 -- floor data function for floor slant
local BIT_FLOOR_DATA_CEILING_SLANT = 0x3 -- floor data function for ceiling slant
local BIT_FLOOR_DATA_TRIGGER = 0x4 -- floor data function for trigger
local BIT_FLOOR_DATA_DEATH = 0x5 -- floor data function for death square
local BIT_FLOOR_DATA_CLIMBABLE = 0x6 -- floor data function for climbable
local BIT_FLOOR_DATA_TRIANGULATION_BEGIN = 0x7 -- floor data function for triangulation
local BIT_FLOOR_DATA_TRIANGULATION_END = 0x12 -- floor data function for triangulation end
local NO_ITEM = 65535 -- identifier for "no item", e.g. end of item linked list
local NO_ROOM = 255 -- identifier for "no room", e.g. not a portal
local NO_FLOOR = -127 -- identifier for "no floor", a wall.
local OBJECT_NUMBER_LARA = 0 -- Lara's object number

local trigger_types = {
  [0]="Trigger",
  "Pad",
  "Switch",
  "Key",
  "Pickup",
  "HeavyTrigger",
  "AntiPad",
  "Combat",
  "Dummy",
}

local actions = {
  [0]="Object",
  "Camera",
  "Current",
  "FlipMap",
  "FlipOn",
  "FlipOff",
  "LookAt",
  "EndLevel",
  "PlaySoundtrack",
  "FlipEffect",
  "SecretFound",
  "ClearBodies",
}

-----------
-- CACHE --
-----------

-- Room cache. All sector and floor data for a room is calculated at run time,
-- when Lara enters a new room - the result is stored here. This cache is cleared
-- when the level changes, ends, or restarts
local rooms = {}

---------------
-- VARIABLES --
---------------
local timer
local room_current
local room_array_pointer, floor_array_pointer, item_array_pointer
local lara_id
local next_active
local end_of_level
local do_refresh = function()
  timer = u32(ram.timer)
  room_current = u32(ram.room_current)
  room_array_pointer = u32(ram.room_array_pointer)
  floor_array_pointer = u32(ram.floor_array_pointer)
  item_array_pointer = u32(ram.item_array_pointer)
  lara_id = u16(ram.lara_id)
  next_active = u16(ram.next_active)
  end_of_level = u32(ram.end_of_level)
end

----------------------
-- HELPER FUNCTIONS --
----------------------
-- Benchmark a function - the elapsed time is returned in ms. Executed once
local benchmark = function(func)
  local before = os.clock()
  func()
  return math.abs(os.clock() - before) * 1000
end

-- Draws some text on the screen at (x, y) and automatically formats args using fmt
local draw = function(x, y, fmt, ...)
  gui.pixelText(x, y, string.format(fmt, ...), 0xFFFFFFFF, 0xFF000000)
end

-- Draws some text from the rights edge of the screen at position y, and automatically formats args using fmt
local draw_right = function(y, fmt, ...)
  local formatted = string.format(fmt, ...)
  local x = SCREEN_WIDTH - (string.len(formatted) * CHAR_WIDTH) -- determine where to draw text
  draw(x, y, formatted)
end

-- Gets the current mouse X and Y as a tuple
local mouse = function()
  local mouse_data = input.getmouse()
  return mouse_data.X, mouse_data.Y
end

-- Returns the raw number of frames of the current level
local frames = function()
  return math.max(timer - 2, 0)
end

-- Returns a table of the number of hours, minutes, seconds and milliseconds for the number of frames provided
-- This is used to get a format string for the current time in the level, to match the stopwatch
local timer = function(time)
  local time = time or frames()
  local seconds = time / 30
  return {
    hours = seconds / 3600,
    minutes = seconds / 60,
    seconds = seconds % 60,
    milliseconds = time % 30,
    frames = time,
  }
end

-- returns a string used by the script detailing the number of hours, minutes, seconds, milliseconds and frames 
-- for the current level so far (the in-game timer)
local get_level_timer_string = function()
  local time = timer()
  return string.format("%02d:%02d.%02d (%d)", time.minutes, time.seconds, time.milliseconds, time.frames)
end

-- draw an arrowhead at (x, y) with provided size and rotation (angle)
-- angle should be in radians
local draw_arrowhead = function(x, y, size, angle, color)
  gui.drawPolygon({
    { -- left side of arrowhead
      x + size * math.sin(angle - 2),
      y - size * math.cos(angle - 2),
    },
    { -- origin
      x,
      y,
    },
    { -- right side of arrowhead
      x + size * math.sin(angle + 2),
      y - size * math.cos(angle + 2),
    },
    { -- tip of arrowhead
      x + size * 2 * math.sin(angle),
      y - size * 2 * math.cos(angle),
    },
  }, nil, nil, 0x0, color)
end

-----------
-- ITEMS --
-----------

-- given an item ID, returns the next active item in the linked list
local item_get_next = function(item_id)
  local offset = item_array_pointer + (STRUCT_LEN_ENTITY * item_id) + 28
  return u16(offset)
end 

-- returns the memory address of the beginning of a specific item's data
local item_get_address = function(item_id)
  return item_array_pointer + item_id * STRUCT_LEN_ENTITY
end 

-- returns true if the item ID is an intelligent entity, i.e. a moveable with health
local item_is_intelligent = function(item_id)
  local base = item_get_address(item_id)
  local health = s16(base + 34)
  return health > 0 -- has health
end

-- returns all currently active item IDs
local item_get_active_all = function()
  local items = {}
  local node = next_active
  while node ~= NO_ITEM do
    if not DRAW_ENTITY_INFO_IGNORE_NON_INTELLIGENT or item_is_intelligent(node) then
      table.insert(items, node)
    end
    node = item_get_next(node)
  end
  return items
end

-- returns the short name of the entity
local item_get_name_short = function(item_id)
  local name = names[item_id]
  return string.sub(name, 0, 6)
end

-- returns the entire ITEM_INFO structure for a given item ID
local item_get_data = function(item_id)
  local base = item_get_address(item_id)
  return {
    addr = base + 32,
    -- floor = s32(base),
    -- touch_bits = u32(base + 4),
    -- mesh_bits = u32(base + 8),
    object_number = s16(base + 12),
    -- current_anim_state = s16(base + 14),
    -- goal_anim_state = s16(base + 16),
    -- required_anim_state = s16(base + 18),
    -- anim_number = s16(base + 20),
    -- frame_number = s16(base + 22),
    room_number = s16(base + 24),
    -- next_item = s16(base + 26),
    next_active = s16(base + 28),
    speed = s16(base + 30),
    fallspeed = s16(base + 32),
    hit_points = s16(base + 34),
    -- box_number = u16(base + 36),
    -- timer = s16(base + 38), 
    -- invisible = s16(base + 40) ~= 0,
    -- shade = s16(base + 42), 
    -- shadeB = s16(base + 44), 
    -- carried_item = s16(base + 46),
    -- data = u32(base + 48),
    x_pos = s32(base + 52),
    y_pos = s32(base + 56),
    z_pos = s32(base + 60),
    -- x_rot = s16(base + 64),
    y_rot = u16(base + 66),
    -- z_rot = s16(base + 68),
    -- flags = u16(base + 70),
    -- flags2 = u16(base + 72),
    -- flags3 = u16(base + 74),
  }
end

-----------
-- ROOMS --
-----------
-- returns the base address of a particular room
local room_get_address = function(room_id)
  return room_array_pointer + (room_id * STRUCT_LEN_ROOM)
end

-- returns the base address for a particular floor data index
local floor_get_address = function(floor_data_index)
  return floor_array_pointer + (floor_data_index * 2)
end

-- returns all floor data for a particular sector.
-- returns a structure like
-- floor = {
--   portal = <Portal ID this sector goes to>
--   death = <True if the sector causes death to Lara>
--   climable = <Climbable bitwise - not used>
--   trigger = <Trigger data>
-- }
local sector_get_floor_data = function(index)
  local floor = {
    portal = NO_ROOM,
    death = false,
    climable = 0,
    trigger = {},
  }

  -- moves to the next floor data index and returns the data there
  local next = function()
    index = index + 1
    return u16(floor_get_address(index))
  end

  while index ~= 0 do
    local address = floor_get_address(index)
    local bytes = u16(address)
    -- floor data is ESSSSSSSXXXAAAAA
    -- E = end bit, when true then stop parsing
    local action = bit.band(bytes, 0x1F)
    -- S = subfunction, used with action to change behaviour
    local subfunction = bit.rshift(bit.band(bytes, 0x7F00), 8)
    -- A = action to perform, e.g. PORTAL or TRIGGER
    local end_flag = bit.rshift(bytes, 15)

    -- DOORS
    if action == BIT_FLOOR_DATA_DOOR then
      -- actual portal is the next byte in floor data
      floor.portal = bit.band(next(), 0xFF)
    -- FLOOR/CEILING SLANT
    elseif action == BIT_FLOOR_DATA_FLOOR_SLANT or action == BIT_FLOOR_DATA_CEILING_SLANT then
      next() -- skip byte
    -- TRIGGER
    elseif action == BIT_FLOOR_DATA_TRIGGER then -- split this into separate function?
      -- trigger setup begins
      local setup = next()
       -- setup is XXMMMMMOTTTTTTTT
      local trigger = {
        -- T = timer, used to wait a certain # of ticks before executing trigger
        timer = bit.band(setup, 0xFF),
        -- O = oneshot, when true then trigger can only be activated once
        oneshot = bit.rshift(bit.band(setup, 0x100), 8),
        -- M = mask, all masks must be activated before trigger will fire
        mask = bit.rshift(bit.band(setup, 0x3E00), 9),
        type = subfunction,
        item = nil, -- not set for now
        targets = {}
      }
      if trigger.type == TRIGGER_TYPE_KEY or trigger.type == TRIGGER_TYPE_SWITCH then 
        -- next byte is the trigger/switch that activates trigger - skip
        next()
      end

      -- for this trigger, calculate all of the targets
      -- each sector can only have one trigger but it can trigger many things.
      local command = nil
      repeat
        -- target setup begins
        -- each target is 2 bytes EAAAAATTTTTTTTTT
        command = next()
        -- A = action, the action to perform, e.g. activate, look at, etc.
        local action = bit.rshift(bit.band(command, 0x7C00), 10)
        -- T = to, the target of the action
        local to = bit.band(command, 0x3FF)
        if action == 1 then
          -- camera trigger - skip
          command = next()
        end
        table.insert(trigger.targets, {
          action = action, -- action to be performed
          to = to -- against this "thing" (depends on action)
        })
        -- E = end flag, used to stop parsing
      until bit.band(command, 0x8000) > 1

      floor.trigger = trigger
    -- DEATH
    elseif action == BIT_FLOOR_DATA_DEATH then
      floor.death = true
    -- CLIMBABLE
    elseif action == BIT_FLOOR_DATA_CLIMBABLE then
      floor.climbable = subfunction
    -- TRIANGULATION
    elseif action >= BIT_FLOOR_DATA_TRIANGULATION_BEGIN and action <= BIT_FLOOR_DATA_TRIANGULATION_END then
      next() -- skip byte
    end

    if end_flag > 0 then break end -- go until we get a signal to stop
    next()
  end 
  return floor
end 

-- function to write some info about a sector
local sector_tooltip = function(x, y, sector)
  -- table to build up strings for the tooltip
  local strings = {}

  -- lambda to display a room, if set, as (to: roomID), or as empty string if not set
  local s = function(room)
    return room ~= NO_ROOM and string.format("(to: %d)", room) or ""
  end

  -- header - display ceiling height (and ceiling portal if exists) and floor height (and floor portal if exists)
  table.insert(strings, 
    string.format("%d^ %s %dv %s",
      sector.ceiling,
      s(sector.sky_room),
      sector.floor,
      s(sector.pit_room)))

  -- if the sector is a portal to a room - regular portal, not ceiling/floor
  if sector.portal ~= NO_ROOM then
    table.insert(strings,
      string.format("DOOR %d",
        sector.portal))
  end

  -- trigger info
  local trigger = sector.trigger
  if trigger and trigger.type then
    -- trigger type - PAD, SWITCH, KEY? and associated metadata
    table.insert(strings,
      string.format("%s ONESHOT:%d MASK:%X TIMER:%d ACTIONS:%d",
        trigger_types[trigger.type] or "UNKNOWN",
        trigger.oneshot,
        trigger.mask,
        trigger.timer,
        #trigger.targets -- Number of targets to be activated
      ))

    if #trigger.targets > 0 then
      -- this trigger triggers "stuff" - display info for all of these
      for n, target in pairs(trigger.targets) do
        local action_string = actions[target.action]
        local item_detail_string = ""
        if target.action == 0 or target.action == 6 then
          -- 0 = activate, 6 = look at. This is used for when the target of the trigger is an item
          local item = item_get_data(target.to)
          item_detail_string = string.format(": %s", names[item.object_number] or "UNKNOWN")
        end
        table.insert(strings,
          string.format("%s %d%s",
              action_string or "UNKNOWN",
              target.to,
              item_detail_string))
      end
    end
  end
  for i, str in pairs(strings) do
    draw(x, y + i * 15, str)
  end
end

local sector_get_data = function(base, count)
  local sectors = {}
  for i = 0, count - 1 do
    local addr = base + (i * STRUCT_LEN_SECTOR)
    local index = u16(addr)
    local sector = {
      pit_room = u8(addr + 4),
      floor = s8(addr + 5),
      sky_room = u8(addr + 6),
      ceiling = s8(addr + 7),
    }
    -- get floor data and merge into sector table (so we can do sector.trigger etc)
    local floor = sector_get_floor_data(index)
    for k, v in pairs(floor) do sector[k] = v end

    sectors[i] = sector
  end
  return sectors
end

local sector_get_colour = function(sector)
  if sector.pit_room ~= NO_ROOM or sector.portal ~= NO_ROOM then
    return DRAW_MAP_COLOUR_DOOR
  elseif sector.trigger.type then 
    return DRAW_MAP_COLOUR_TRIGGER
  elseif sector.floor == NO_FLOOR and sector.ceiling == NO_FLOOR then
    return DRAW_MAP_COLOUR_WALL
  end
  return DRAW_MAP_COLOUR_DEFAULT
end

local room_get_data = function(id)
  local base = room_get_address(id)
  local sector_ptr = u32(base + 8)
  local depth = s16(base + 40)
  local width = s16(base + 42)
  local sectors = sector_get_data(sector_ptr, width * depth)
  return {
    x = s32(base + 20),
    y = s32(base + 24),
    z = s32(base + 28),
    minfloor = s32(base + 32),
    maxceiling = s32(base + 36),
    x_size = width,
    y_size = depth,
    sectors = sectors,
  }
end

-------------
-- DRAWING --
-------------

-- draws the level timer on screen
local draw_timer = function()
  local timer_string = get_level_timer_string()
  draw(DRAW_TIMER_INFO_X, DRAW_TIMER_INFO_Y, timer_string)
end

-- draws information about Lara's data: position, speed, health etc.
local draw_lara = function()
  local lara = item_get_data(lara_id)
  local health = math.max(lara.hit_points / 10, 0)

  draw(DRAW_LARA_INFO_X, DRAW_LARA_INFO_Y,      "%.02f%%", health)
  draw(DRAW_LARA_INFO_X, DRAW_LARA_INFO_Y + 15, "%+05dX, %+05dY, %+05dZ", lara.x_pos, lara.y_pos, lara.z_pos)
  draw(DRAW_LARA_INFO_X, DRAW_LARA_INFO_Y + 30, "%.02f", lara.y_rot)
  draw(DRAW_LARA_INFO_X, DRAW_LARA_INFO_Y + 45, "%d, %d", lara.speed, lara.fallspeed)
end

-- draws single line info about the provided room
local draw_room_info = function(room)
  -- cache room
  if not rooms[room] then rooms[room] = room_get_data(room) end
  local data = rooms[room]

  draw(DRAW_ROOM_INFO_X, DRAW_ROOM_INFO_Y,
    "Room #%d %dx %d^ %dv %dz %dx%d",
      room,
      data.x / SECTOR_PIXELS,
      data.maxceiling,
      data.minfloor,
      data.z / SECTOR_PIXELS,
      data.x_size,
      data.y_size)
end

-- draws an item on the minimap
local draw_item_position_minimap = function(room, item)
  local is_lara = item.object_number == 0
  local color = is_lara and DRAW_MAP_COLOUR_LARA or DRAW_MAP_COLOUR_ENEMY

  -- bottom of the map
  local map_bottom = DRAW_MAP_Y + (room.y_size * DRAW_MAP_SCALE)

  -- relative item position based on origin of room
  local item_x = (item.x_pos - room.x) / 1024
  local item_z = (item.z_pos - room.z) / 1024

  -- where to draw initial enemy position relative to the map
  local origin_x = DRAW_MAP_X + item_x * DRAW_MAP_SCALE
  local origin_y = map_bottom - (item_z * DRAW_MAP_SCALE)

  -- work out angle of the item
  local angle = (item.y_rot / 0xFFFF) * 360 * (math.pi / 180)
  draw_arrowhead(origin_x, origin_y, DRAW_MAP_ARROWHEAD_SIZE, angle, color)
end

-- draws a minimap on the screen of the specified room
-- any items provided in the [items] variable are drawn on the minimap, if they are in the room
local draw_minimap = function(room, items)
  if not rooms[room] then rooms[room] = room_get_data(room) end
  local data = rooms[room]
  local mouse_x, mouse_y = mouse()
  local info_x = 0
  local info_y = DRAW_MAP_Y + (data.y_size + 2) * DRAW_MAP_SCALE

  for id, sector in pairs(data.sectors) do
    local column = math.floor(id / data.y_size)
    local row = data.y_size - (id % data.y_size) - 1
    local x = column * DRAW_MAP_SCALE + DRAW_MAP_X
    local y = row * DRAW_MAP_SCALE + DRAW_MAP_Y
    local to_x = x + DRAW_MAP_SCALE
    local to_y = y + DRAW_MAP_SCALE
    local colour = sector_get_colour(sector)

    if mouse_x >= x and mouse_x < to_x and mouse_y >= y and mouse_y < to_y then
      sector_tooltip(info_x, info_y, sector)
      colour = DRAW_MAP_COLOUR_HOVER
    end

    gui.drawBox(x, y, to_x, to_y, DRAW_MAP_COLOUR_BACKGROUND, colour)
  end

  for _, i in pairs(items) do
    local item = item_get_data(i)

    if item.object_number == OBJECT_NUMBER_LARA -- is Lara
    or item.room_number == room then -- or is an item in the current room
      draw_item_position_minimap(data, item)
    end
  end
end

-- draws details of all "active" enemies on the screen
local draw_item_info = function(items)
  local head = next_active
  local mx, my = mouse()
  table.sort(items)

  for i, item in pairs (items) do
    local data = item_get_data(item)
    local identifier = item ~= head and '' or '*'
    local name = item_get_name_short(data.object_number)
    local hp = data.hit_points <= 0 and 0 or data.hit_points
    local x = data.x_pos / SECTOR_PIXELS
    local y = data.y_pos / SECTOR_PIXELS
    local z = data.z_pos / SECTOR_PIXELS

    draw_right(DRAW_ENTITY_INFO_Y + (i * 15),
      "%s%3d: %-6s %03d%6.02f%6.02f%6.02f",
        identifier,
        item,
        name,
        hp,
        data.x_pos / SECTOR_PIXELS,
        data.y_pos / SECTOR_PIXELS,
        data.z_pos / SECTOR_PIXELS )
  end
end

-- draws current movie information (frames, rerecords)
local draw_movie_info = function()
  local mode = movie.mode()
  local frame_count = emu.framecount()
  local movie_length = movie.length()
  local rerecords = movie.getrerecordcount()

  draw(DRAW_MOVIE_INFO_X, DRAW_MOVIE_INFO_Y,      "%s", mode)
  draw(DRAW_MOVIE_INFO_X, DRAW_MOVIE_INFO_Y + 15, "%d / %d (%d)", frame_count, movie_length, rerecords)
end

----------
-- MAIN --
----------
gui.cleartext()
gui.clearGraphics()

local STATE_IDLE = 1
local STATE_LEVEL = 2
local STATE_LEVEL_COMPLETE = 3
local state = STATE_IDLE

-- state handler for idle, this could be out of level or in inventory etc
local do_state_idle = function()
  -- do nothing but check if the level has started again
  if end_of_level == 0 then
    state = STATE_LEVEL
  end
end

-- state handler for end of level
local do_state_level_complete = function()
  -- level completion - clear cache variables and move to idle state
  rooms = {}
  state = STATE_IDLE
end

-- state handler for in-level
local do_state_level = function()
  -- check for level complete
  if end_of_level ~= 0 then
    state = STATE_LEVEL_COMPLETE
    return
  end
  -- fetch all currently active items
  -- used by the minimap and mini item info features
  local items = item_get_active_all()

  -- draw all 
  if DO_DRAW_TIMER then
    draw_timer()
  end
  if DO_DRAW_LARA_INFO then
    draw_lara()
  end
  if DO_DRAW_ITEM_MINI_INFO then
    draw_item_info(items)
  end
  if DO_DRAW_MINIMAP then
    table.insert(items, lara_id)
    draw_minimap(room_current, items)
  end
  if DO_DRAW_MOVIE_INFO then
    draw_movie_info()
  end
  if DO_DRAW_ROOM_INFO then
    draw_room_info(room_current)
  end
end

local states = {
  [STATE_IDLE] = do_state_idle,
  [STATE_LEVEL] = do_state_level,
  [STATE_LEVEL_COMPLETE] = do_state_level_complete,
}

local main = function()
  do_refresh()
  states[state]()
end

while true do
  local elapsed = benchmark(main)
  draw_right(0, "%.04fms", elapsed)
  emu.frameadvance()
end
-- event.onframeend(main)