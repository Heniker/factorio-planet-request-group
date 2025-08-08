-- https://lua-api.factorio.com/latest/concepts/LogisticFilter.html
-- https://lua-api.factorio.com/latest/classes/LuaLogisticSection.html
-- https://lua-api.factorio.com/latest/index-runtime.html
Util = require "mod.util"

local IS_DEBUG = true

-- how to access this from info.json?
local mod_name = "planet-request-group"

-- https://lua-api.factorio.com/latest/concepts/SpaceLocationID.html
local neutral_import_location = "solar-system-edge"
local stkey_space_platform_to_numeric_id = "space_platform_numeric_id"
local stkey_previous_mod_version = "previous_mod_version"
local generated_logistic_name_prefix = "__gen_"
local setting_is_strict_pattern = "planet-request-group-is-strict-pattern"
local setting_inverse_search_pattern = "planet-request-group-inverse-search-pattern"
-- %p matches `>` for some reason
local planet_search_pattern = "%[planet=([^%]]+)%][%s%.%-%+,&]*"

local mylog = function(arg)
  if IS_DEBUG then log(arg) end
end

--- @param name string
--- @return table<integer, LuaPlanet>?
local get_planets_from_group = function(name)
  if (not name) then return end

  mylog("get_planets_from_group : " .. Util.wrap(name))

  local is_strict = settings.global[setting_is_strict_pattern].value

  --- @type table<integer, string>
  local group_planets = {}
  local _, lastEnds = name:find(
    "^[%s%.%-%+,&]*" .. Util.escape_lua_pattern(settings.global[setting_inverse_search_pattern].value) .. "[%s%.%-%+,&]*")

  lastEnds = lastEnds or 0

  -- finds the first unbroken sequence of planet icons
  while true do
    local start, ends, match = name:find(planet_search_pattern, lastEnds)

    if (not start or not ends) then break end
    if (is_strict and start ~= lastEnds and start ~= lastEnds + 1) then break end
    lastEnds = ends

    table.insert(group_planets, match)
  end

  --- @type table<integer, LuaPlanet>
  local result = Util.map(
    function(it)
      return Util.find(function(game_planet) return game_planet.name == it end, game.planets)
    end,
    Util.deduplicate(group_planets)
  )

  mylog(
    "get_planets_from_group result:" .. Util.wrap(serpent.line(Util.map(function(it) return it.name end, result)))
  )

  if (next(result)) then return result end
end

--- @param name string
local is_inverse_from_group = function(name)
  if (not name) then return end

  mylog("is_inverse_from_group : " .. Util.wrap(name))

  local is_strict = settings.global[setting_is_strict_pattern].value
  local search_pattern = settings.global[setting_inverse_search_pattern].value

  local start = name:find(search_pattern, 0, true)

  if (not start) then
    mylog("is_inverse_from_group result: " .. Util.wrap("false"))
    return false
  end
  if (is_strict and start ~= 1) then
    mylog("is_inverse_from_group result: " .. Util.wrap("false"))
    return false
  end

  mylog("is_inverse_from_group result: " .. Util.wrap("true"))
  return true
end

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not logistic_section or not logistic_section.valid) then return end
  if (not logistic_section.owner or not logistic_section.owner.surface or not logistic_section.owner.surface.platform) then return end
  if (not logistic_section.owner.valid or not logistic_section.owner.surface.valid or not logistic_section.owner.surface.platform.valid) then return end
  if (not logistic_section.filters) then return end
  if (not logistic_section.active) then return end
  if (logistic_section.group == "") then return end
  if (logistic_section.group:find("^" .. generated_logistic_name_prefix)) then return end


  local current_location_planet_proto = logistic_section.owner.surface.platform.space_location
  if (not current_location_planet_proto) then return end
  local section_name_planets = get_planets_from_group(logistic_section.group)
  local is_inverse = is_inverse_from_group(logistic_section.group)

  if (not section_name_planets and is_inverse) then
    section_name_planets = {}
  end

  if (not section_name_planets) then return end

  local generated_section = Util.find(function(it) return it.group:find("^" .. generated_logistic_name_prefix) end,
    logistic_section.owner.get_logistic_sections().sections)

  if (not generated_section) then
    local platform_id = logistic_section.owner.surface.platform.index
    generated_section =
        logistic_section.owner.get_logistic_sections().add_section(generated_logistic_name_prefix .. platform_id)
  end

  if (not generated_section) then return end

  local has_current_planet_in_group_name = Util.find(
    function(it) return current_location_planet_proto.name == it.name end,
    section_name_planets
  )

  if (has_current_planet_in_group_name and is_inverse) then return end
  if (not has_current_planet_in_group_name and not is_inverse) then return end

  for k, v in pairs(logistic_section.filters) do
    if (not v.value) then goto continue end

    v.import_from = neutral_import_location
    logistic_section.set_slot(k, v)

    --- @type LogisticFilter
    local copy = Util.clone_shallow(v)
    copy.import_from = current_location_planet_proto

    local isOk = pcall(function()
      generated_section.set_slot(generated_section.filters_count + 1, copy)
    end)

    if (not isOk) then
      local slot, id = Util.find(function(it) return serpent.line(it.value) == serpent.line(v.value) end,
        generated_section.filters)

      -- Small safety measure
      if (not id) then goto continue end

      copy.min = copy.min + slot.min

      isOk = pcall(function() generated_section.set_slot(id, copy) end)
    end

    if (not isOk) then
      mylog("Logistic section error")
    end

    ::continue::
  end
end

--- @param entity LuaEntity
local function update_for_entity(entity)
  if (not entity or not entity.valid) then return end
  if (not entity or not entity.surface or not entity.surface.platform) then return end

  mylog("update_for_entity: " .. Util.wrap(entity.surface.platform.name))

  local logistic_sections_api = entity.get_logistic_sections()
  if (not logistic_sections_api) then return end

  local logistic_sections = logistic_sections_api.sections
  if (not logistic_sections) then return end

  for _, section in pairs(logistic_sections) do
    update_logistic_section(section)
  end
end

--- @param entity LuaEntity
local function restore_sections(entity)
  if (not entity or not entity.valid) then return end
  if (not entity or not entity.surface or not entity.surface.platform) then return end

  mylog("restore_sections for: " .. Util.wrap(entity.surface.platform.name))

  local logistic_sections_api = entity.get_logistic_sections()
  if (not logistic_sections_api) then return end

  local logistic_sections = logistic_sections_api.sections
  if (not logistic_sections) then return end

  for _, section in pairs(logistic_sections) do
    if (section.group == '') then goto continue end

    if (section.group:find("^" .. generated_logistic_name_prefix)) then
      section.filters = {}
      logistic_sections_api.remove_section(section.index)
    end

    ::continue::
  end
end

-- script.on_event(defines.events.on_gui_closed, function(event)
--   for _, it in pairs(game.surfaces) do
--     if (not it.platform or not it.platform.valid) then goto continue end
--     if (not it.platform.hub or not it.platform.hub.valid) then goto continue end

--     init_storage(it.platform.index)
--     update_for_entity(it.platform.hub)

--     ::continue::
--   end
-- end)

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
  if not (event and event.player_index) then return end
  if not (event.section and event.section.owner and event.section.owner.surface and event.section.owner.surface.platform) then return end
  if not (event.section.owner.surface.platform.hub and event.section.owner.surface.platform and event.section.owner.surface.platform.hub) then return end
  if (event.section.group:find("^" .. generated_logistic_name_prefix)) then return end

  mylog("on_entity_logistic_slot_changed: " .. Util.wrap(event.section.group))

  restore_sections(event.section.owner.surface.platform.hub)
  update_for_entity(event.section.owner.surface.platform.hub)
end)

local lastTick = 0
script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if (not event) then return end
  if (not event.platform.valid) then return end
  if (not event.platform.hub or not event.platform.hub.valid) then return end
  if (event.platform.state == event.old_state) then return end

  if (event.tick < lastTick + 10) then return end
  lastTick = event.tick

  mylog("on_space_platform_changed_state: Update for " .. Util.wrap(event.platform.name))

  if (event.platform.state == defines.space_platform_state.waiting_at_station
        or event.platform.state == defines.space_platform_state.no_schedule) then
    update_for_entity(event.platform.hub)
  else
    restore_sections(event.platform.hub)
  end
end)

script.on_configuration_changed(function(event)
  if (not script.active_mods[mod_name]) then return end

  local current_mod_version = Util.version_to_number(script.active_mods[mod_name])
  local prev_mod_version = storage[stkey_previous_mod_version] or 0

  mylog("MIGRATION: Current_mod_version: " .. Util.wrap(current_mod_version))

  -- reenable sections that were previously disabled by the mod
  if (prev_mod_version <= 104) then
    mylog("MIGRATION: Running migration from version 104...")

    -- so Factorio team added ability to manage groups like a month ago...
    -- I'm gonna pretend I do not know about that and continue like it's not there
    -- https://forums.factorio.com/viewtopic.php?t=120136
    for _, it in pairs(game.surfaces) do
      if (not it.platform or not it.platform.valid) then goto continue end
      if (not it.platform.hub or not it.platform.hub.valid) then goto continue end

      local logistic_sections_api = it.platform.hub.get_logistic_sections()
      if (not logistic_sections_api) then goto continue end

      local logistic_sections = logistic_sections_api.sections
      if (not logistic_sections) then goto continue end

      for _, section in pairs(logistic_sections) do
        if (section.group == '') then goto continue end

        -- there used to be now way to use only 'inverse' pattern
        -- so this should be sufficient
        if (section.group:find(planet_search_pattern)) then
          mylog("MIGRATION: Section set to active: " .. Util.wrap(section.group))
          section.active = true
        end

        ::continue::
      end

      ::continue::
    end
  end


  storage[stkey_previous_mod_version] = current_mod_version
end)
