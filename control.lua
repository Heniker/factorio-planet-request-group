-- https://lua-api.factorio.com/latest/concepts/LogisticFilter.html
-- https://lua-api.factorio.com/latest/classes/LuaLogisticSection.html
-- https://lua-api.factorio.com/latest/index-runtime.html
Util = require "mod.util"

local IS_DEBUG = false

-- https://lua-api.factorio.com/latest/concepts/SpaceLocationID.html
local default_neutral_import_location = "solar-system-edge"
local generated_logistic_name_prefix = "__gen_"
local setting_is_strict_pattern = "planet-request-group-is-strict-pattern"
local setting_inverse_search_pattern = "planet-request-group-inverse-search-pattern"

-- compitability with https://mods.factorio.com/mod/osha_launch_control
local neutral_location_markers = { ["[space-location=orbital-connection]"] = "orbital-connection" }

local devlog = function(arg)
  if IS_DEBUG then log(serpent.line(arg)) end
end

--- @param name string
--- @return table<integer, LuaPlanet>?
local parse_group_planets = function(name)
  if (not name) then return end

  devlog("parse_group_planets: " .. Util.wrap(name))

  local _skip = "[%s%.%-%+,&]*"
  local planet_search_pattern = _skip .. "%[planet=([^%]]+)%]" .. _skip
  local is_strict = settings.global[setting_is_strict_pattern].value

  local _inverse_icon = Util.escape_lua_pattern(settings.global[setting_inverse_search_pattern].value)
  local inverse_pattern_start, inverse_pattern_ends = name:find("^" .. _skip .. _inverse_icon .. _skip)

  --- @type table<integer, string>
  local group_planet_names = {}
  local lastEnds = 0

  if (is_strict and inverse_pattern_ends) then
    if inverse_pattern_start ~= 1 then return end
    lastEnds = inverse_pattern_ends
  end

  while true do
    local start, ends, match = name:find(planet_search_pattern, lastEnds)

    if (not start or not ends) then break end
    if (is_strict and start ~= lastEnds + 1) then break end
    lastEnds = ends

    table.insert(group_planet_names, match)
  end

  --- @type table<integer, LuaPlanet>
  local planets = Util.map(
    function(it)
      return Util.find(function(game_planet) return game_planet.name == it end, game.planets)
    end,
    Util.deduplicate(group_planet_names)
  )

  if (inverse_pattern_ends) then
    planets = Util.difference(game.planets, planets)
  end

  devlog(
    "parse_group_planets result: " .. Util.wrap(Util.map(function(it) return it.name end, planets))
  )

  if (next(planets)) then return planets end
end

--- @param name string
local get_neutral_location_from_group = function(name)
  if (not name) then return end

  -- I don't want to implement proper 'strict' parsing for this for now
  --- @type string, string
  local v = Util.find(function(v, k) return name:find(k, 0, true) end, neutral_location_markers)
  if (v) then
    return v
  end
end

--- @param logistic_sections_api LuaLogisticSections
--- @param gen_id number|string
local function find_create_generated_section(logistic_sections_api, gen_id)
  if (not logistic_sections_api) then return end

  local logistic_sections = logistic_sections_api.sections
  local generated_section = Util.find(function(it) return it.group:find("^" .. generated_logistic_name_prefix) end,
    logistic_sections)

  if (not generated_section) then
    generated_section =
        logistic_sections_api.add_section(generated_logistic_name_prefix .. gen_id)
  end

  return generated_section
end

--- @param logistic_section LuaLogisticSection
local function is_managed_section(logistic_section)
  if (not next(logistic_section.filters) or not logistic_section.active) then return end
  if (logistic_section.group == "") then return end
  if (logistic_section.group:find("^" .. generated_logistic_name_prefix)) then return end
  if (not parse_group_planets(logistic_section.group)) then return end
  return true
end

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not Util.safeget(logistic_section).owner.surface.platform.space_location()) then return end
  if (not is_managed_section(logistic_section)) then return end

  devlog("Update for section: " .. Util.wrap(logistic_section.group))

  local platform = logistic_section.owner.surface.platform
  ---@cast platform -?

  local section_name_planets = parse_group_planets(logistic_section.group)
  if (not section_name_planets) then return end

  local has_current_planet_in_group_name = Util.find(
    function(it) return platform.space_location.name == it.name end,
    section_name_planets
  )
  if (not has_current_planet_in_group_name) then return end

  local neutral_import_location = get_neutral_location_from_group(logistic_section.group) or
      default_neutral_import_location

  -- handling of the simple case - no generated section required
  if (#section_name_planets == 1 and neutral_import_location == default_neutral_import_location) then
    for k, v in pairs(logistic_section.filters) do
      if (not v.value) then goto continue end

      v.import_from = platform.space_location
      local isOk = pcall(function() logistic_section.set_slot(k, v) end)

      if (not isOk) then
        devlog("!!! planet-request-group: control.lua:141")
      end

      ::continue::
    end
    return
  end

  local generated_section = find_create_generated_section(logistic_section.owner.get_logistic_sections(),
    platform.index)
  if (not generated_section) then return end

  for k, v in pairs(logistic_section.filters) do
    if (not v.value) then goto continue end

    v.import_from = neutral_import_location
    logistic_section.set_slot(k, v)

    --- @type LogisticFilter
    local copy = Util.clone_shallow(v)
    copy.import_from = platform.space_location
    if (copy.min) then copy.min = copy.min * logistic_section.multiplier end
    if (copy.max) then copy.max = copy.max * logistic_section.multiplier end

    local isOk = pcall(function()
      generated_section.set_slot(generated_section.filters_count + 1, copy)
    end)

    if (not isOk) then
      local slot, id = Util.find(function(it) return serpent.line(it.value) == serpent.line(v.value) end,
        generated_section.filters)

      -- Small safety measure
      if (not id) then goto continue end
      if (copy.min and slot.min) then copy.min = copy.min + slot.min end

      isOk = pcall(function() generated_section.set_slot(id, copy) end)
    end

    -- never happened
    if (not isOk) then
      devlog("!!! Failed to set filters on generated logistic section")
    end

    ::continue::
  end
end

--- @param entity LuaEntity
local function update_for_entity(entity)
  if (not Util.safeget(entity).surface.platform()) then return end

  devlog("update_for_entity: " .. Util.wrap(entity.surface.platform.name))

  local logistic_sections_api = entity.get_logistic_sections()
  if (not logistic_sections_api) then return end

  local logistic_sections = logistic_sections_api.sections

  for _, section in pairs(logistic_sections) do
    update_logistic_section(section)
  end
end

--- @param entity LuaEntity
local function restore_sections(entity)
  if (not Util.safeget(entity).surface.platform()) then return end

  devlog("restore_sections for: " .. Util.wrap(entity.surface.platform.name))

  local logistic_sections_api = entity.get_logistic_sections()
  if (not logistic_sections_api) then return end

  -- edge case if user deleted generated section - still need to reset filters on it
  -- so generating section again just to remove it is fine
  local generated_section = find_create_generated_section(logistic_sections_api, entity.surface.platform.index)
  if (not generated_section) then return end

  generated_section.filters = {}
  logistic_sections_api.remove_section(generated_section.index)

  for _, section in pairs(logistic_sections_api.sections) do
    if (not is_managed_section(section)) then goto continue end

    for index, filter in pairs(section.filters) do
      filter.import_from = default_neutral_import_location
      section.set_slot(index, filter)
    end
    ::continue::
  end
end

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
  if (not Util.safeget(event).section.owner.surface.platform.hub()) then return end
  if (not event.player_index) then return end
  if (event.section.group:find("^" .. generated_logistic_name_prefix)) then return end

  local platform = event.section.owner.surface.platform
  ---@cast platform -?

  devlog("on_entity_logistic_slot_changed: " .. Util.wrap(event.section.group))

  restore_sections(platform.hub)
  if (platform.state == defines.space_platform_state.waiting_at_station) then
    update_for_entity(platform.hub)
  end
end)

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if (not Util.safeget(event).platform.hub()) then return end
  if (event.platform.state == event.old_state) then return end

  if (IS_DEBUG) then
    local _, state = Util.find(function(it) return it == event.platform.state end, defines.space_platform_state)

    devlog("on_space_platform_changed_state: Update for " ..
      Util.wrap(event.platform.name) .. " . Platform state: " .. Util.wrap(state))
  end

  restore_sections(event.platform.hub)
  if (event.platform.state == defines.space_platform_state.waiting_at_station) then
    update_for_entity(event.platform.hub)
  end
end)

script.on_configuration_changed(function(event)
  local changes = event.mod_changes[script.mod_name]
  local _old_version = changes and changes.old_version
  if (not _old_version) then return end

  local old_version = Util.version_to_number(_old_version)
  local current_version = Util.version_to_number(script.active_mods[script.mod_name])

  devlog("MIGRATION: Current_mod_version: " .. Util.wrap(current_version))

  if (old_version <= Util.version_to_number('0.1.4')) then
    -- reenable sections that were previously disabled by the mod
    devlog("MIGRATION: Running migration from version 104...")

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

        local planet_search_pattern = "%[planet=([^%]]+)%]"

        -- there used to be no way to use only 'inverse' pattern
        -- so this should be sufficient
        if (section.group:find(planet_search_pattern)) then
          game.print(script.mod_name .. ": section enabled after migration - " .. section.group)
          devlog("MIGRATION: Section set to active: " .. Util.wrap(section.group))
          section.active = true
        end

        ::continue::
      end

      ::continue::
    end
  end
end)
