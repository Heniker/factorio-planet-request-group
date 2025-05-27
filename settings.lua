data:extend({
  {
    type = "string-setting",
    name = "planet-request-group-default-search-pattern",
    setting_type = "runtime-global",
    order = "aa",
    hidden = true,
    default_value = "%[planet=([^%]]+)%]",
  },
  {
    type = "string-setting",
    name = "planet-request-group-any-search-pattern",
    order = "ab",
    hidden = true,
    setting_type = "runtime-global",
    default_value = "%[virtual%-signal=signal%-anything%]",
  }
})
