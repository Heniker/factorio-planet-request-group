local exports = {}

function is_null(arg) return arg == nil end
exports.is_null = is_null

function is_not_null(arg) return arg ~= nil end
exports.is_not_null = is_not_null

-- auto filters for null values because of how lua works
function map(fun, t)
  local result = {}
  for i, v in pairs(t) do
    result[i] = fun(v, i)
  end
  return result
end
exports.map = map

function filter(predicate, t)
  local result = {}
  for i, v in pairs(t) do
    if predicate(v, i) then
      result[i] = v
    end
  end
  return result
end
exports.filter = filter

function find(predicate, t)
  for i, v in pairs(t) do
    if predicate(v, i) then
      return v, i
    end
  end
end
exports.find = find

function contains(needle, t)
  return find(function(it) return it == needle end, t) ~= nil
end
exports.contains = contains

function intersection(t1, t2)
  return filter(function(x) return contains(x, t2) end, t1)
end
exports.intersection = intersection

function difference(t1, t2)
  return filter(function(x) return not contains(x, t2) end, t1)
end
exports.difference = difference

function key_of(t)
  local r = {}
  for k, v in pairs(t) do
    table.insert(r, k)
  end
  return r
end
exports.key_of = key_of

function invert_keyvalue(t)
  local r = {}
  for k, v in pairs(t) do
    r[v] = k
  end
  return r
end
exports.invert_keyvalue = invert_keyvalue

function size_of(t)
  local cnt = 0
  for _ in pairs(t) do
    cnt = cnt + 1
  end
  return cnt
end
exports.size_of = size_of

function clone_shallow(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end
exports.clone_shallow = clone_shallow

function deduplicate(t)
  local result = {}

  for _, v in pairs(t) do
    result[v] = 1
  end

  return key_of(result)
end
exports.deduplicate = deduplicate

function version_to_number(str)
  local major, minor, patch = str:match("^(%d+)%.?(%d*)%.?(%d*)$")
  major = tonumber(major) or 0
  minor = tonumber(minor) or 0
  patch = tonumber(patch) or 0
  return major * 10000 + minor * 100 + patch * 1
end
exports.version_to_number = version_to_number

function wrap(str, s1, s2)
  s1 = s1 or "<"
  s2 = s2 or ">"
  return tostring(s1) .. serpent.line(str) .. tostring(s2)
end
exports.wrap = wrap

function escape_lua_pattern(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end
exports.escape_lua_pattern = escape_lua_pattern

---@generic T
---@param t T|nil
---@return T
function safeget(t)
  return setmetatable({}, {
    __index = function(_, key)
      if t == nil or t["valid"] == false then return safeget(nil) end
      return safeget(t[key])
    end,
    __call = function(_, default)
      if t and t["valid"] == false then return default end
      return t or default
    end
  })
end

exports.safeget = safeget

return exports
