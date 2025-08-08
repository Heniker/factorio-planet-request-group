local exports = {}

local is_null = function(arg) return arg == nil end
exports.is_null = is_null

local is_not_null = function(arg) return arg ~= nil end
exports.is_not_null = is_not_null

-- auto filters for null values because of how lua works
local map = function(fun, list)
  local result = {}
  for i, v in pairs(list) do
    result[i] = fun(v, i)
  end
  return result
end
exports.map = map

local filter = function(predicate, list)
  local result = {}
  for i, v in pairs(list) do
    if predicate(v, i) then
      result[i] = v
    end
  end
  return result
end
exports.filter = filter

local find = function(predicate, list)
  for i, v in pairs(list) do
    if predicate(v, i) then
      return v, i
    end
  end
end
exports.find = find

local contains = function(needle, list)
  return find(function(it) return it == needle end, list) ~= nil
end
exports.contains = contains

local intersection = function(t1, t2)
  return filter(function(x) return contains(x, t2) end, t1)
end
exports.intersection = intersection

local difference = function(t1, t2)
  return filter(function(x) return not contains(x, t2) end, t1)
end
exports.difference = difference

local key_of = function(t)
  local r = {}
  for k, v in pairs(t) do
    table.insert(r, k)
  end
  return r
end
exports.key_of = key_of

local size_of = function(t)
  local cnt = 0
  for _ in pairs(t) do
    cnt = cnt + 1
  end
  return cnt
end
exports.size_of = size_of

local clone_shallow = function(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end
exports.clone_shallow = clone_shallow

local symmetric_difference = function(t1, t2)
  local result = {}

  for _, v in pairs(t1) do
    if not contains(v, t2) then
      table.insert(result, v)
    end
  end

  for _, v in pairs(t2) do
    if not contains(v, t1) then
      table.insert(result, v)
    end
  end

  return result
end
exports.symmetric_difference = symmetric_difference

local deduplicate = function(t)
  local result = {}

  for _, v in pairs(t) do
    result[v] = 1
  end

  return key_of(result)
end
exports.deduplicate = deduplicate

local version_to_number = function(str)
  local major, minor, patch = str:match("^(%d+)%.?(%d*)%.?(%d*)$")
  major = tonumber(major) or 0
  minor = tonumber(minor) or 0
  patch = tonumber(patch) or 0
  return major * 10000 + minor * 100 + patch * 1
end
exports.version_to_number = version_to_number

local wrap = function(str, s1, s2)
  s1 = s1 or "<"
  s2 = s2 or ">"
  return tostring(s1) .. tostring(str) .. tostring(s2)
end
exports.wrap = wrap

local escape_lua_pattern = function(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"))
end
exports.escape_lua_pattern = escape_lua_pattern

return exports
