local util = {}

function util.tablefind(t, path)
  local pathelements = string.gmatch(path, "([^.]+)%.?")
  local item = t

  for element in pathelements do
    if type(item) ~= "table" then item = nil; break end

    item = item[element]
  end

  return item
end

return util
