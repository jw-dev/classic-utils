return { 
  ["5651035B"] = { -- Tomb Raider I (USA) (v1.6)
    name = "tomb1", 
    ram = {
      lag_frames = 0x89100, -- number of lag frame counter, reset when non-lag frame
      timer = 0x89A3C, -- address of in-game timer
      room_current = 0x89C50, -- address of current room (Lara position)
      room_list = 0xDD564,
      floor_array_pointer = 0x89BF4, -- address of the pointer to the current level's floor data
      item_array_pointer = 0x89BFC, -- address of the pointer to the current entity active list
      lara_id = 0x1DDFF0, -- address of Lara's current entity ID
      level_current = 0x87668, -- address of current level ID
      next_active = 0x89D50, -- item number of the next active item (head of linked list)
      end_of_level = 0x890F8, -- true when there is no level loaded
    },
    entity_pos_offset = 48, -- how many bytes into the entity struct the position vector is
    struct_len_sector = 8, -- how many bytes each sector data is
    struct_len_room = 68, -- how many bytes each room is
    struct_len_entity = 72, -- how many bytes each entity is
  },
  ["02EEB617"] = { -- Tomb Raider II (PAL) 
    name = "tomb2",
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
    entity_pos_offset = 52,
    struct_len_sector = 8, -- how many bytes each sector data is
    struct_len_room = 80, -- how many bytes each room is
    struct_len_entity = 0x4C, -- how many bytes each entity is
  },
}