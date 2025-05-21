--- @param name string
local function get_planet_from_name(name)
  if (not name) then return end

  -- [planet=aquilo]
  for _, planet in pairs(game.planets) do
    local item_planet_name = string.match(name, settings.global["PlanetRequestGroup-default-search-pattern"].value)
    if (item_planet_name and string.find(item_planet_name, planet.name, 1, true)) then return planet end
  end
end

--- @param name string
local function is_any_planet_from_name(name)
  if (not name) then return end

  -- [virtual-signal=signal-anything]
  if string.find(name, settings.global["PlanetRequestGroup-any-search-pattern"].value) then return true end
end

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not logistic_section or not logistic_section.valid or not logistic_section.filters or not logistic_section.group) then return end

  local proto
  if (is_any_planet_from_name(logistic_section.group)) then
    if (not logistic_section.owner or not logistic_section.owner.surface or not logistic_section.owner.surface.platform or not logistic_section.owner.surface.platform.space_location) then return end
    proto = logistic_section.owner.surface.platform.space_location
  else
    local planet = get_planet_from_name(logistic_section.group)
    if (not planet) then return end
    proto = planet.prototype
  end

  for k, v in pairs(logistic_section.filters) do
    v.import_from = proto

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

script.on_event(defines.events.on_gui_closed, function(event)
  if (not event.entity or not event.entity.valid) then return end
  update_for_entity(event.entity)
end)

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event)
  if (not event.section or not event.section.valid) then return end
  update_logistic_section(event.section)
end)

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if (not event.platform.valid or not event.platform.state == defines.space_platform_state.waiting_at_station) then return end
  if (not event.platform.hub or not event.platform.hub.valid) then return end
  if (not event.platform.space_location) then return end
  update_for_entity(event.platform.hub)
end)
