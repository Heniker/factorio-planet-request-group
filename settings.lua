data:extend({
  {
    type = "bool-setting",
    name = "planet-request-group-is-strict-pattern",
    order = "aa",
    setting_type = "runtime-global",
    default_value = true
  },
  {
    type = "string-setting",
    name = "planet-request-group-inverse-search-pattern",
    order = "ab",
    setting_type = "runtime-global",
    default_value = "[virtual-signal=signal-anything]",
    allowed_values = { "[virtual-signal=signal-anything]", "[virtual-signal=signal-deny]", "[virtual-signal=signal-no-entry]", "[virtual-signal=signal-output]", "[virtual-signal=signal-not-equal]", "[virtual-signal=up-arrow]", "[virtual-signal=down-arrow]", "[virtual-signal=signal-heart]" }
  }
})
