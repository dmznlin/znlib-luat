--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2026-03-20
  描述： 命令编码、验证
-------------------------------------------------------------------------------]]
local tag     = "cmd-utils"
local utils   = {
  verify    = "verify",   --验证字段
  ver_lower = true,       --验证小写
  key_des   = "znlib-go", --加密秘钥
  key_msg   = ""          --消息秘钥

}
utils.__index = utils

function utils:new()
  local obj = {}
  setmetatable(obj, utils)
  return obj
end

---加密数据
---@param plain string 明文
---@return string 密文Base64
function utils:des_encrypt(plain)
  local dt = crypto.cipher_encrypt("DES-ECB", "PKCS7", plain, self.key_des)
  return crypto.base64_encode(dt)
end

---解密数据
---@param data string 密文
---@return string 明文
function utils:des_decrypt(data)
  local dt = crypto.base64_decode(data)
  return crypto.cipher_decrypt("DES-ECB", "PKCS7", dt, self.key_des)
end

---按顺序编码
---@param cmd table 命令
---@param order table 顺序
---@return string|nil json文本
---@return string|nil 验证码
function utils:encode(cmd, order)
  if order == nil then return nil end
  local isLong, ver_item = nil, nil
  --检索verify字段

  for _, item in pairs(order) do
    if isLong == nil then
      if cmd[item.long] ~= nil then
        isLong = true
      elseif cmd[item.short] ~= nil then
        isLong = false
      end
    end

    if ver_item == nil and item.long == self.verify then
      ver_item = item
    end

    if isLong and ver_item then
      break
    end
  end

  --无效的顺序描述
  if ver_item == nil then
    return nil
  end

  local en_cmd = function ()
    local data = "{"
    for _, item in pairs(order) do
      local val = nil
      if isLong then
        val = cmd[item.long]
      else
        val = cmd[item.short]
      end

      if val then
        if item.omit then --零值时不提交
          local tp = type(val)
          if tp == "string" and val == "" then
            goto continue
          end

          if tp == "number" and val == 0 then
            goto continue
          end
        end

        if #data > 1 then
          data = data .. ","
        end

        data = data .. string.format('"%s":', item.short)
        if type(val) == "number" then
          data = data .. tostring(val)
        else
          data = data .. string.format('"%s"', val)
        end
      end

      --跳转坐标
      ::continue::
    end

    return data .. "}"
  end

  if #self.key_msg > 0 then
    if isLong then
      cmd[ver_item.long] = self.key_msg
    else
      cmd[ver_item.short] = self.key_msg
    end

    --计算验证码
    local new_key = crypto.md5(en_cmd())
    if utils.ver_lower then --默认大写
      new_key = string.lower(new_key)
    end

    if isLong then
      cmd[ver_item.long] = new_key
    else
      cmd[ver_item.short] = new_key
    end

    return en_cmd(), new_key
  end

  return en_cmd(), nil
end

---解码并验证
---@param data string 数据
---@param order table 顺序
---@return table|nil 命令
function utils:decode(data, order)
  if order == nil then return nil end
  local cmd, err = json.decode(data)

  if cmd == nil or type(cmd) ~= "table" then
    log.info(tag, "无效的命令格式(json)")
    return nil
  end

  local isLong, ver_item = nil, nil
  --检索verify字段
  for _, item in pairs(order) do
    if isLong == nil then
      if cmd[item.long] ~= nil then
        isLong = true
      elseif cmd[item.short] ~= nil then
        isLong = false
      end
    end

    if ver_item == nil and item.long == self.verify then
      ver_item = item
    end

    if isLong and ver_item then
      break
    end
  end

  --无效的顺序描述
  if ver_item == nil then
    return nil
  end

  if #self.key_msg > 0 then
    local old_key = "" --backup key
    if isLong then
      old_key = cmd[ver_item.long]
    else
      old_key = cmd[ver_item.short]
    end

    local _, new_key = self:encode(cmd, order)
    if new_key ~= old_key then
      return nil
    end
  end

  --已是长字段
  if isLong then
    return cmd
  end

  --短字段名转长字段别名
  local cmd_new = {}
  for _, item in pairs(order) do
    local val = cmd[item.short]
    if val then
      cmd_new[item.long] = val
    end
  end

  return cmd_new
end

return utils

--[[-----------------------------------------------------------------------------
local cmd = require("znlib_cmd"):new()
cmd.verify = "verify"
cmd.ver_lower = true
cmd.key_msg = "我是消息秘钥"

--编码顺序描述
--short: 发送时短字段
--long: 发开时长字段
--omit: 零值时不提交
local cmd_order = {
  { short = "c", long = "cmd" },                --命令字
  { short = "s", long = "sender" },             --发送方
  { short = "v", long = "verify", omit = true } --验证字段
}

--编码
local dt = cmd:encode({
  cmd = 10,
  sender = "hello",
  verify = "1"
}, cmd_order)
log.info("cmd", dt)

--解码
local new_cmd = cmd:decode(dt, cmd_order)
log.info("cmd", utils.table_to_str(new_cmd))
-------------------------------------------------------------------------------]]
