--- @param name string
--- @return table<string, LuaPlanet>?
local function get_planets_from_name(name)
  if (not name) then return end

  local pattern = settings.global["planet-request-group-default-search-pattern"].value
  local planets = {}

  for match in string.gmatch(name, pattern) do
    for _, planet in pairs(game.planets) do
      if string.find(match, planet.name, 1, true) then
        table.insert(planets, planet)
      end
    end
  end

  if next(planets) then return planets end
  return nil
end

--- @param name string
local function is_any_from_name(name)
  if (not name) then return end

  local pattern = settings.global["planet-request-group-any-search-pattern"].value

  if string.find(name, pattern) then return true end
end

--- @param name LuaPlanet | data.PlanetPrototype
local function get_alternate_location(planet)
  for _, p in pairs(game.planets) do
    if (p.name ~= planet.name) then return p end
  end
end

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not logistic_section or not logistic_section.valid or not logistic_section.filters or not logistic_section.group) then return end
  if (not logistic_section.owner or not logistic_section.owner.surface or not logistic_section.owner.surface.platform or not logistic_section.owner.surface.platform.space_location) then return end
  if (not logistic_section.owner.valid or not logistic_section.owner.surface.valid or not logistic_section.owner.surface.platform.valid) then return end

  local current_location_planet_proto = logistic_section.owner.surface.platform.space_location
  if (not current_location_planet_proto) then return end
  local section_name_planets = get_planets_from_name(logistic_section.group)
  if (not section_name_planets) then return end

  local action = nil
  local reaction = nil
  if (is_any_from_name(logistic_section.group)) then
    action = function() return get_alternate_location(current_location_planet_proto).prototype end
    reaction = function() return current_location_planet_proto end
  else
    action = function() return current_location_planet_proto end
    reaction = function() return get_alternate_location(current_location_planet_proto).prototype end
  end

  local result_import_proto = nil

  for _, planet in pairs(section_name_planets) do
    if current_location_planet_proto.name == planet.name then
      result_import_proto = action()
      goto continue
    end
    ::continue::
  end

  if not result_import_proto then
    result_import_proto = reaction()
  end

  for k, v in pairs(logistic_section.filters) do
    v.import_from = result_import_proto

    logistic_section.set_slot(k, v)
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

-- script.on_event(defines.events.on_gui_closed, function(event)
--   if (not event.entity or not event.entity.valid) then return end
--   update_for_entity(event.entity)
-- end)

-- script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
--   if (not event.section or not event.section.valid) then return end
--   update_logistic_section(event.section)
-- end)

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if (not event.platform.valid or not event.platform.state == defines.space_platform_state.waiting_at_station) then return end
  if (not event.platform.hub or not event.platform.hub.valid) then return end
  if (not event.platform.space_location) then return end
  update_for_entity(event.platform.hub)
end)
