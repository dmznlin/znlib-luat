--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2025-05-07
  描述： 辅助工具类

  备注:
  1.部分函数引用:
    @author 杰神
    @license GPLv3
-------------------------------------------------------------------------------]]
local tag = "utils"
local utils = {}

--- 删除目录,以及下面所有的子目录和文件
---@param path string 目录
function utils.remove_all(path)
  local ret, data = io.lsdir(path, 50, 0)
  if not ret then
    return
  end

  for _, e in ipairs(data) do
    local fn = path .. e.name
    if e.type == 1 then
      utils.remove_all(fn .. "/")
      log.info(tag, "remove dir", fn)
      io.rmdir(fn)
    else
      os.remove(fn)
      log.info(tag, "remove file", fn)
    end
  end

  -- 继续遍历
  if #data == 50 then
    utils.remove_all(path)
  end
end

function utils.walk(path, results, offset)
  log.info(tag, "walk")
  offset = offset or 0

  local ret, data = io.lsdir(path, 50, offset)
  if not ret then
    return
  end

  for _, e in ipairs(data) do
    local fn = path .. e.name
    if e.type == 1 then
      log.info(tag, "walk", fn)
      utils.walk(fn .. "/", results)
    else
      log.info(tag, "walk", fn, e.size)
      if results then
        table.insert(results, {
          name = fn,
          size = e.size
        })
      end
    end
  end

  -- 继续遍历
  if #data == 50 then
    utils.walk(path, results, offset + 50)
  end
end

function utils.inspect(data, prefix)
  prefix = prefix or ""

  local tp = type(data)
  log.info(tag, "inspect", prefix, tp, data)

  if tp == "table" then
    for k, v in pairs(data) do
      if v ~= data then
        utils.inspect(v, prefix .. "." .. k)
      end
    end
  end
end

---------------------------------------------------------------------------------
local id_base = 0  --序列基准
local id_date = "" --时间基准

--[[
  描述: 生成业务流水号
  格式:
    1.6位设备ID: device_id 后6位
    2.6位日期: 2位年 月 日
    3.6位时间: 时 分 秒
    4.序列号
--]]
function utils.make_id()
  local str = os.date("%y%m%d%H%M%S")
  if str ~= id_date then --时间变更,重置序列
    if id_base >= 9 then
      id_base = 0
    end

    id_date = tostring(str)
  end

  id_base = id_base + 1
  return string.sub(device_id, #device_id - 5) .. str .. tostring(id_base)
end

---系统信息
function utils.sys_info()
  local info = {}
  info["sys.name"] = PROJECT
  info["sys.ver"] = VERSION
  info["sys.core"] = rtos.version()

  info["id.cpu"] = mcu.unique_id():toHex()
  info["id.dev"] = device_id

  info["mem.sys"] = string.format("%d,%d,%d", rtos.meminfo("sys")) -- 系统内存
  info["mem.lua"] = string.format("%d,%d,%d", rtos.meminfo("lua")) -- 虚拟机内存

  if libgnss and libgnss.isFix() then                              --已定位
    local loc = libgnss.getRmc(2) or {}
    info["gps.lat"] = loc.lat                                      --纬度, 正数为北纬, 负数为南纬
    info["gps.lng"] = loc.lng                                      --经度, 正数为东经, 负数为西经

    local gsa = libgnss.getGsa()
    info["gps.gsa"] = gsa.sats --正在使用的卫星编号
  end

  return info
end

--[[
  date: 2025-05-04
  parm: 字符串
  desc: 将str转为16进制表示
--]]
function utils.str_to_hex(str)
  local first = true
  return string.gsub(str, "(.)", function (x)
    local ret = string.format(first and "%02X" or " %02X", string.byte(x))
    if first then first = false end
    return ret
  end)
end

--[[
    date: 2025-05-04
    parm: 16进制字符串(55 AA)
    desc: 将hex转为字符串
  --]]
function utils.str_from_hex(hex)
  local str = hex:gsub("[%s%p]", ""):upper()
  return str:gsub("%x%x", function (c)
    return string.char(tonumber(c, 16))
  end)
end

--[[
    date: 2025-05-05
    parm: 时间字符串
    desc: 将sTime转为日期格式
  --]]
function utils.time_from_str(sTime)
  local year, month, day, hour, minute, second = sTime:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
  return os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = minute,
    sec = second
  })
end

--[[
    date: 2025-05-07
    parm: 字节
    desc: 将val转为bit数组
  --]]
function utils.byte_to_bit(val)
  local bits = {}
  for i = 7, 0, -1 do
    -- 右移 i 位，并与 1 进行按位与操作
    local bit = (val >> i) & 1
    table.insert(bits, bit)
  end

  return bits
end

--[[
  date: 2025-05-01
  parm: value 字符串
  desc: 字符串转table
--]]
function utils.table_from_str(value)
  if not value or value == "" then
    return nil, "table string empty"
  end

  -- 使用 load 安全地解析字符串
  local chunk, err = load("return " .. value)
  if not chunk then
    return nil, "table string invalid: " .. (err or "unknown error")
  end

  -- 执行并返回解析后的 table
  local success, result = pcall(chunk)
  if not success then
    return nil, "convert string failed: " .. result
  end

  return result or {}
end

--[[
  date: 2025-05-01
  parm: precision 浮点精度,默认2
  desc: table转字符串
--]]
function utils.table_to_str(tbl, precision)
  local to_str = function (value)
    if type(value) == 'table' then
      return utils.table_to_str(value)
    elseif type(value) == 'string' then
      return "\'" .. value .. "\'"
    else
      return tostring(value)
    end
  end

  if tbl == nil then return "" end
  local ret = "{"

  local idx = 1
  for key, value in pairs(tbl) do
    local signal = ","
    if idx == 1 then
      signal = ""
    end

    if key == idx then
      ret = ret .. signal .. to_str(value)
    else
      if type(key) == 'number' or type(key) == 'string' then
        ret = ret .. signal .. '[' .. to_str(key) .. "]=" .. to_str(value)
      else
        if type(key) == 'userdata' then
          ret = ret .. signal .. "*s" .. utils.table_to_str(getmetatable(key)) ..
              "*e" .. "=" .. to_str(value)
        else
          ret = ret .. signal .. key .. "=" .. to_str(value)
        end
      end
    end

    idx = idx + 1
  end

  ret = ret .. "}"
  return ret
end

--[[
  date: 2025-05-07
  parm: old,原内容;new,新内容
  desc: 替换table中的内容
--]]
function utils.table_replace(tbl, old, new)
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      tbl[k] = v:gsub(old, new)
    elseif type(v) == "table" then
      utils.table_replace(v, old, new)
    end
  end
end

return utils
