-- TR2 PAL version for PSX.
-- Game hash: 02EEB617
return {
  ram = {
    lag_frames = 0x8A120, -- number of lag frame counter, reset when non-lag frame
    timer = 0xDE7E0, -- address of in-game timer
    room_current = 0x8B3FC, -- address of current room (Lara position)
    room_array_pointer = 0x8A660, -- address of the pointer to the current level's room array
    floor_array_pointer = 0x8AC2C, -- address of the pointer to the current level's floor data
    item_array_pointer = 0x8AC34, -- address of the pointer to the current entity active list
    lara_id = 0x8C658, -- address of Lara's current entity ID
    level_current = 0x89E80, -- address of current level ID
    next_active = 0x8B6CA, -- item number of the next active item (head of linked list)
    end_of_level = 0x89E68, -- true when there is no level loaded
  },
  sector_pixels = 1024, -- how many pixels each sector in a physical TR level has
  struct_len_sector = 8, -- how many bytes each sector data is
  struct_len_room = 80, -- how many bytes each room is
  struct_len_entity = 0x4C, -- how many bytes each entity is
  bit_floor_data_door = 0x1, -- floor data function for portal
  bit_floor_data_floor_slant = 0x2, -- floor data function for floor slant
  bit_floor_data_ceiling_slant = 0x3, -- floor data function for ceiling slant
  bit_floor_data_trigger = 0x4, -- floor data function for trigger
  bit_floor_data_death = 0x5, -- floor data function for death square
  bit_floor_data_climbable = 0x6, -- floor data function for climbable
  bit_floor_data_triangulation_begin = 0x7, -- floor data function for triangulation
  bit_floor_data_triangulation_end = 0x12, -- floor data function for triangulation end
  no_item = 65535, -- identifier for "no item", e.g. end of item linked list
  no_room = 255, -- identifier for "no room", e.g. not a portal
  no_floor = -127, -- identifier for "no floor", a wall.
}