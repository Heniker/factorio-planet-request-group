-- https://lua-api.factorio.com/latest/concepts/LogisticFilter.html
-- https://lua-api.factorio.com/latest/classes/LuaLogisticSection.html
-- https://lua-api.factorio.com/latest/index-runtime.html
Util = require "mod.util"

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

--- @param name string
--- @return table<integer, LuaPlanet>?
local function get_planets_from_group(name)
  if (not name) then return end

  local is_strict = settings.global[setting_is_strict_pattern].value

  --- @type table<integer, string>
  local group_planets = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  local _, lastEnds = name:find(
    "^[%s%.%-%+,&]*" .. settings.global[setting_inverse_search_pattern].value .. "[%s%.%-%+,&]*", 0, true)

  -- finds the first unbroken sequence of planet icons
  while true do
    local start, ends, match = name:find(planet_search_pattern, lastEnds)

    if (not start or not ends) then break end
    if (is_strict and lastEnds and start ~= lastEnds and start ~= lastEnds + 1) then break end
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

  -- log(
  --   "parsed planets from group <" ..
  --   name .. "> : <" .. serpent.line(Util.map(function(it) return it.name end, result)) .. ">"
  -- )

  if (next(result)) then return result end
end

--- @param name string
local function is_inverse_from_group(name)
  if (not name) then return end

  local is_strict = settings.global[setting_is_strict_pattern].value
  local search_pattern = settings.global[setting_inverse_search_pattern].value

  ---@diagnostic disable-next-line: param-type-mismatch
  local start = name:find(search_pattern, 0, true)

  if (not start) then return false end
  if (is_strict and start ~= 1) then return false end

  return true
end

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not logistic_section or not logistic_section.valid) then return end
  if (not logistic_section.owner or not logistic_section.owner.surface or not logistic_section.owner.surface.platform) then return end
  if (not logistic_section.owner.valid or not logistic_section.owner.surface.valid or not logistic_section.owner.surface.platform.valid) then return end
  if (not logistic_section.active) then return end
  if (logistic_section.group == "") then return end
  if (logistic_section.group:find("^" .. generated_logistic_name_prefix)) then return end

  local current_location_planet_proto = logistic_section.owner.surface.platform.space_location
  if (not current_location_planet_proto) then return end
  local section_name_planets = get_planets_from_group(logistic_section.group)

  if (not section_name_planets and is_inverse_from_group(logistic_section.group)) then
    section_name_planets = {}
  end

  if (not section_name_planets) then return end

  local generated_section
  for k, v in pairs(logistic_section.owner.get_logistic_sections().sections) do
    if (v.group:find("^" .. generated_logistic_name_prefix)) then
      generated_section = v
      break
    end
  end

  if (not generated_section) then
    local platform_id = storage[stkey_space_platform_to_numeric_id][logistic_section.owner.surface.platform.index]
    generated_section =
        logistic_section.owner.get_logistic_sections().add_section(generated_logistic_name_prefix .. platform_id)
  end

  if (not generated_section) then return end

  local result_import_proto = nil

  for _, planet in pairs(section_name_planets) do
    if (current_location_planet_proto.name ~= planet.name) then
      goto continue
    end

    if (is_inverse_from_group(logistic_section.group)) then return end
    result_import_proto = current_location_planet_proto
    break

    ::continue::
  end

  if (not result_import_proto) then
    if (not is_inverse_from_group(logistic_section.group)) then return end
    result_import_proto = current_location_planet_proto
  end

  for k, v in pairs(logistic_section.filters) do
    if (not v.value) then goto continue end

    v.import_from = neutral_import_location
    logistic_section.set_slot(k, v)

    --- @type LogisticFilter
    local copy = Util.clone_shallow(v)
    copy.import_from = result_import_proto

    local isOk = pcall(function()
      generated_section.set_slot(generated_section.filters_count + 1, copy)
    end)

    if (not isOk) then
      local _, id = Util.find(function(it) return serpent.line(it.value) == serpent.line(v.value) end,
        generated_section.filters)

      if (not id) then return end

      local slot = generated_section.get_slot(id)
      copy.min = copy.min + slot.min

      isOk = pcall(function() generated_section.set_slot(id, copy) end)
    end

    if (not isOk) then
      log("Logistic section error")
    end

    ::continue::
  end
end

--- @param entity LuaEntity
local function update_for_entity(entity)
  if (not entity or not entity.valid) then return end

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

function init_storage(platform_index)
  storage[stkey_space_platform_to_numeric_id] = storage[stkey_space_platform_to_numeric_id] or {}

  local storage_platforms = storage[stkey_space_platform_to_numeric_id]

  local game_platform_ids = Util.map(function(it) return it.platform and it.platform.index end, game.surfaces)
  local removed_platform_id = next(Util.difference(Util.key_of(storage_platforms), game_platform_ids))

  if (not storage_platforms[platform_index] and removed_platform_id) then
    storage_platforms[platform_index] = storage_platforms[removed_platform_id]

    storage_platforms[removed_platform_id] = nil
  end

  if (not storage_platforms[platform_index]) then
    storage_platforms[platform_index] = Util.size_of(storage_platforms)
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

-- script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
--   for _, it in pairs(game.surfaces) do
--     if (not it.platform or not it.platform.valid) then goto continue end
--     if (not it.platform.hub or not it.platform.hub.valid) then goto continue end

--     init_storage(it.platform.index)
--     update_for_entity(it.platform.hub)

--     ::continue::
--   end
-- end)

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if (not event.platform.valid) then return end
  if (not event.platform.hub or not event.platform.hub.valid) then return end
  if (event.platform.state == event.old_state) then return end

  init_storage(event.platform.index)

  if (event.platform.state == defines.space_platform_state.waiting_at_station
        or event.platform.state == defines.space_platform_state.no_schedule) then
    log("running update for " .. event.platform.name)
    update_for_entity(event.platform.hub)
  else
    log("restoring section for " .. event.platform.name)
    restore_sections(event.platform.hub)
  end
end)

script.on_configuration_changed(function(event)
  local current_mod_version = Util.version_to_number(script.active_mods[mod_name])
  local prev_mod_version = storage[stkey_previous_mod_version] or 0

  -- log("current_mod_version")
  -- log(current_mod_version)

  -- reenable sections that were previously disabled by the mod
  if (prev_mod_version <= 104) then
    for _, it in pairs(game.surfaces) do
      if (not it.platform or not it.platform.valid) then goto continue end
      if (not it.platform.hub or not it.platform.hub.valid) then goto continue end

      local logistic_sections_api = it.platform.hub.get_logistic_sections()
      if (not logistic_sections_api) then goto continue end

      local logistic_sections = logistic_sections_api.sections
      if (not logistic_sections) then goto continue end

      for _, section in pairs(logistic_sections) do
        if (section.group == '') then goto continue end

        if (section.group:find(planet_search_pattern)) then
          section.active = true
        end

        ::continue::
      end

      ::continue::
    end
  end


  storage[stkey_previous_mod_version] = current_mod_version
end)
