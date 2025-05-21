data:extend({
  {
    type = "string-setting",
    name = "PlanetRequestGroup-default-search-pattern",
    setting_type = "runtime-global",
    order = "aa",
    default_value = "%[planet=([^%]]+)%]",
  },
  {
    type = "string-setting",
    name = "PlanetRequestGroup-any-search-pattern",
    order = "ab",
    setting_type = "runtime-global",
    default_value = "%[virtual%-signal=signal%-anything%]",
  }
})
