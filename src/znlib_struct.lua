--[[-----------------------------------------------------------------------------
  作者:  dmzn@163.com 2026-03-17
  描述:  c-style struct library
-------------------------------------------------------------------------------]]
local tag = "c-struct"
local struct = {}

--大小端
struct.le = "le"
struct.be = "be"

local endian_marks = {
  le = "<", -- little-endian(小端)
  be = ">"  -- big-endian(大端)
}

local type_def = {
  bool = {
    size = 1,
    encode = function (v, endian)
      return string.char(v and 1 or 0)
    end,
    decode = function (s, pos, endian)
      local b = string.byte(s, pos)
      return b ~= 0, pos + 1
    end
  },
  int8 = {                        -- 整数类型
    size = 1,
    encode = function (v, endian) -- endian参数仅兼容
      return string.char(v & 0xFF)
    end,
    decode = function (s, pos, endian)
      local b = string.byte(s, pos)
      return b > 0x7F and b - 0x100 or b, pos + 1
    end
  },
  uint8 = {
    size = 1,
    encode = function (v, endian)
      return string.char(v & 0xFF)
    end,
    decode = function (s, pos, endian)
      return string.byte(s, pos), pos + 1
    end
  },
  int16 = {
    size = 2,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "i2", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "i2", s, pos)
    end
  },
  uint16 = {
    size = 2,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "I2", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "I2", s, pos)
    end
  },
  int32 = {
    size = 4,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "i4", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "i4", s, pos)
    end
  },
  uint32 = {
    size = 4,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "I4", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "I4", s, pos)
    end
  },

  float = { -- 浮点类型
    size = 4,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "f", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "f", s, pos)
    end
  },
  double = {
    size = 8,
    encode = function (v, endian)
      local mark = endian_marks[endian] or "<"
      return string.pack(mark .. "d", v)
    end,
    decode = function (s, pos, endian)
      local mark = endian_marks[endian] or "<"
      return string.unpack(mark .. "d", s, pos)
    end
  },

  string = function (len) -- 字符串类型
    return {
      size = len,
      encode = function (v, endian)
        local s = tostring(v):sub(1, len)
        return s .. string.rep(string.char(0), len - #s)
      end,
      decode = function (s, pos, endian)
        local str = string.sub(s, pos, pos + len - 1)
        str = str:gsub("%z+$", "")
        return str, pos + len
      end
    }
  end
}

--[[ 1.定义结构体(endian 可选参数,默认 le/小端)
-- 成员列表扩展: {name = "成员名", type = "类型名"[, len = 长度, endian = "le/be"]}
-- 结构体级 endian: 统一设置所有成员的端序(成员级 endian 优先级更高)
--]]
function struct.define(name, members, struct_endian)
  local struct_def = {
    name = name,
    members = {},
    total_size = 0,
    endian = struct_endian or "le" -- 结构体默认端序: 小端
  }

  -- 校验并初始化成员
  for i, mem in ipairs(members) do
    if not mem.name or not mem.type then
      znlib.show_log(string.format("struct %s 成员 %d 缺少 name/type 字段", name, i))
    end

    -- 成员端序: 优先使用成员自身配置,否则继承结构体端序
    local mem_endian = mem.endian or struct_def.endian
    if mem_endian ~= "le" and mem_endian ~= "be" then
      znlib.show_log(string.format("struct %s 成员 %s 端序仅支持 le/be,当前: %s", name, mem.name, mem_endian))
    end

    local type_info
    if mem.type == "string" then
      if not mem.len or type(mem.len) ~= "number" or mem.len <= 0 then
        znlib.show_log(string.format("struct %s 成员 %s(string 类型)必须指定合法的 len", name, mem.name))
      end
      type_info = type_def.string(mem.len)
    else
      type_info = type_def[mem.type]
      if not type_info then
        znlib.show_log(string.format("struct %s 成员 %s 不支持的类型: %s", name, mem.name, mem.type))
      end
    end

    struct_def.members[i] = {
      name = mem.name,
      type = mem.type,
      len = mem.len,
      endian = mem_endian, -- 记录成员最终端序
      type_info = type_info,
      offset = struct_def.total_size
    }
    struct_def.total_size = struct_def.total_size + type_info.size
  end

  struct[name] = struct_def
  return struct_def
end

-- 2. 结构体转字节数组
function struct.pack(name, data)
  local struct_def = struct[name]
  if not struct_def then
    znlib.show_log("未定义的结构体: " .. name)
  end

  local bytes = {}
  for _, mem in ipairs(struct_def.members) do
    local val = data[mem.name]
    if val == nil then
      znlib.show_log(string.format("结构体 %s 缺少成员 %s", name, mem.name))
    end

    -- 类型适配
    if mem.type:find("int") or mem.type:find("uint") then
      val = math.tointeger(val) or tonumber(val)
      if not val then
        znlib.show_log(string.format("结构体 %s 成员 %s 必须是整数", name, mem.name))
      end
    elseif mem.type == "float" or mem.type == "double" then
      val = tonumber(val)
      if not val then
        znlib.show_log(string.format("结构体 %s 成员 %s 必须是数字", name, mem.name))
      end
    end

    -- 编码: 传递成员端序
    table.insert(bytes, mem.type_info.encode(val, mem.endian))
  end

  return table.concat(bytes)
end

-- 3. 字节数组解析为结构体
function struct.unpack(name, bytes)
  local struct_def = struct[name]
  if not struct_def then
    znlib.show_log("未定义的结构体: " .. name)
  end

  if #bytes ~= struct_def.total_size then
    znlib.show_log(string.format("结构体 %s 期望字节长度 %d,实际 %d", name, struct_def.total_size, #bytes))
  end

  local data = {}
  local pos = 1
  for _, mem in ipairs(struct_def.members) do
    -- 解码: 传递成员端序
    local val, new_pos = mem.type_info.decode(bytes, pos, mem.endian)
    data[mem.name] = val
    pos = new_pos
  end

  return data
end

-- 辅助函数: 打印结构体定义
function struct.print_def(name)
  local struct_def = struct[name]
  if not struct_def then
    print("未定义的结构体: " .. name)
    return
  end

  print(string.format("结构体 %s(总长度: %d 字节,默认端序: %s): ",
    struct_def.name, struct_def.total_size, struct_def.endian == "le" and "小端" or "大端"))
  for _, mem in ipairs(struct_def.members) do
    print(string.format("  %s: %s(偏移: %d 字节,长度: %d 字节,端序: %s)",
      mem.name, mem.type, mem.offset, mem.type_info.size, mem.endian == "le" and "小端" or "大端"))
  end
end

return struct

--[[-----------------------------------------------------------------------------
local struct = require("znlib_struct")
local s_name = "demoA"

-- 示例1：结构体级指定大端，部分成员覆盖为小端
struct.define(s_name, {
  { name = "uint16_be", type = "uint16" },                     -- 继承结构体大端
  { name = "uint16_le", type = "uint16", endian = struct.le }, -- 覆盖为小端
  { name = "float_be", type = "float" },                       -- 继承结构体大端
  { name = "str", type = "string", len = 5 }                   -- 字符串无大小端
}, struct.be)                                                  -- 结构体默认大端

-- 打印结构体定义(含端序信息)
struct.print_def(s_name)

-- 构造数据并打包
local test_data = {
  uint16_be = 0x1234,
  uint16_le = 0x1234,
  str = "abc",
  float_be = 3.14
}

local byte_array = struct.pack(s_name, test_data)
print(utils.str_to_hex(byte_array))

-- 解包验证
local unpacked = struct.unpack(s_name, byte_array)
print("\n解包结果: ")
print("uint16_be(大端):", unpacked.uint16_be) -- 输出 0x1234
print("uint16_le(小端):", unpacked.uint16_le) -- 输出 0x1234
print("float_be(大端):", unpacked.float_be) -- 输出 3.14
print("str:", unpacked.str) -- 输出 "abc"

-- 示例2：默认小端(原有方式)
s_name = "demoB"
struct.define(s_name, {
  { name = "int32",  type = "int32" },
  { name = "double", type = "double" }
}) -- 无第三个参数，默认小端
struct.print_def(s_name)
-------------------------------------------------------------------------------]]
