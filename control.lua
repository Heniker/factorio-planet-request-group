local stkey_space_platform_to_numeric_id = "space_platform_numeric_id"
local stkey_space_platform_count = "space_platform_total_count"
local logistic_name_postfix_legacy = '     ||@'
local generated_logistic_name_prefix = '__gen_'

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

--- @param logistic_section LuaLogisticSection
local function update_logistic_section(logistic_section)
  if (not logistic_section or not logistic_section.valid or not logistic_section.filters or not logistic_section.group or logistic_section.group == "") then return end
  if (not logistic_section.owner or not logistic_section.owner.surface or not logistic_section.owner.surface.platform or not logistic_section.owner.surface.platform.space_location) then return end
  if (not logistic_section.owner.valid or not logistic_section.owner.surface.valid or not logistic_section.owner.surface.platform.valid) then return end

  local current_location_planet_proto = logistic_section.owner.surface.platform.space_location
  if (not current_location_planet_proto) then return end
  local section_name_planets = get_planets_from_name(logistic_section.group)
  if (not section_name_planets) then return end

  local generated_section
  for k, v in pairs(logistic_section.owner.get_logistic_sections().sections) do
    if (v.group:find("^" .. generated_logistic_name_prefix)) then generated_section = v end
  end

  if (not generated_section) then
    local platform_id = storage[stkey_space_platform_to_numeric_id][logistic_section.owner.surface.platform.index]
    generated_section = logistic_section.owner.get_logistic_sections().add_section("__gen_" .. platform_id)
  end

  if (not generated_section) then return end

  logistic_section.active = false

  local result_import_proto = nil

  for _, planet in pairs(section_name_planets) do
    if current_location_planet_proto.name ~= planet.name then
      goto continue
    end

    if is_any_from_name(logistic_section.group) then return end
    result_import_proto = current_location_planet_proto
    break

    ::continue::
  end

  if (not result_import_proto) then
    if not is_any_from_name(logistic_section.group) then return end
    result_import_proto = current_location_planet_proto
  end

  for k, v in pairs(logistic_section.filters) do
    v.import_from = result_import_proto
    pcall(function()
      generated_section.set_slot(generated_section.filters_count + 1, v)
    end)
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
      goto continue
    end

    -- legacy --
    local name = section.group:match("^(.-)" .. logistic_name_postfix_legacy)
    if (not name) then goto continue end

    section.group = name

    ::continue::
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
  if (not event.platform.valid) then return end
  if (not event.platform.hub or not event.platform.hub.valid) then return end
  if (event.platform.state == event.old_state) then return end

  storage[stkey_space_platform_to_numeric_id] = storage[stkey_space_platform_to_numeric_id] or {}
  storage[stkey_space_platform_count] = storage[stkey_space_platform_count] or 0

  -- why yes, this table only grows bigger
  if (not storage[stkey_space_platform_to_numeric_id][event.platform.index]) then
    storage[stkey_space_platform_to_numeric_id][event.platform.index] = storage[stkey_space_platform_count]
    storage[stkey_space_platform_count] = storage[stkey_space_platform_count] + 1
  end

  if (event.platform.state == defines.space_platform_state.waiting_at_station) then
    update_for_entity(event.platform.hub)
  else
    restore_sections(event.platform.hub)
  end
end)
