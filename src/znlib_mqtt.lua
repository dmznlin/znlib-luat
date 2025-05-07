--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2025-05-07
  描述： mqtt协议,支持多客户端
-------------------------------------------------------------------------------]]
local tag = "mqtt"
--class
local MQTT = {}

--[[
  date: 2025-05-07
  desc: 创建mqtt实例
--]]
function MQTT:new()
  local obj = {}
  setmetatable(obj, self)
  self.__index = self

  obj.client = nil
  return obj
end

--[[
  date: 2025-05-07
  parm: id,客户端标识;cfg_name,配置项
  desc: 创建mqtt客户端并连接到服务器
--]]
---@param client_id string
---@return boolean
function MQTT:open(client_id, cfg_name)
  if mqtt == nil then
    log.info(tag, "本bsp未适配mqtt库,请查证")
    return false
  end

  if client_id == nil then
    log.info(tag, "open: 无效的 id 参数")
    return false
  end

  cfg_name = (cfg_name ~= nil) and cfg_name or tag
  local cfg = require("znlib_cfg").load_default(cfg_name, { enable = false })
  if not cfg.enable then
    log.info(tag, "通过配置项禁用mqtt功能")
    return false
  end

  --替换$ID$
  utils.table_replace(cfg, "%$id%$", client_id)

  --默认发布主题
  self.pub_def = ""
  for k, v in pairs(cfg.pubs) do
    log.info(tag, "pub", v.topic)
    if #self.pub_def < 1 or v.def == true then
      self.pub_def = k
    end
  end

  if #self.pub_def < 1 then
    log.info(tag, "没有可用(default)的发布主题")
    return false
  end

  for k, v in pairs(cfg.subs) do
    log.info(tag, "sub", v.topic)
  end

  self.client = mqtt.create(nil, cfg.host, cfg.port)
  if self.client == nil then
    log.error(tag, "create client failed")
    return false
  end

  self.id = cfg.client_id
  self.subs = cfg.subs
  self.pubs = cfg.pubs
  self.online = cfg.online

  self.client:auth(self.id, cfg.user_name, cfg.password) -- 鉴权
  self.client:keepalive(cfg.keep_alive)                  -- 默认值240s
  self.client:autoreconn(true, cfg.re_conn)              -- 自动重连机制

  if self.offline ~= nil then                            --离线通知
    local off = cfg.offline
    self.client:will(off.topic, off.msg, off.qos, off.retain)
  end

  -- 注册回调
  self.client:on(function (client, event, topic, payload)
    if event == "conack" then
      local topics = {}
      for k, v in pairs(self.pubs) do
        topics[v.topic] = v.qos
      end

      client:subscribe(topics) --多主题订阅
      log.info(tag, self.id, "连接成功.")
      sys.publish(Status_Mqtt_Connected, self.id)

      if self.online ~= nil then --上线通知
        client:publish(self.online.topic, self.online.msg,
          self.online.qos, self.online.retain)
      end
    elseif event == "recv" then
      sys.publish(Status_Mqtt_SubData, topic, payload, self.id)
    elseif event == "sent" then
    elseif event == "disconnect" then
      log.info(tag, self.id, "已断开.")
    end
  end)

  log.info(tag, self.id, "连接中...")
  self.client:connect()
  sys.waitUntil(Status_Mqtt_Connected)
  return self.client:ready()
end

---@param topic string|nil 主题
---@param payload string 数据
---@param qos integer|nil 质量
---@return integer 消息id
function MQTT:publish(topic, payload, qos)
  if topic == nil then
    local def = self.pubs[self.pub_def]
    topic = def.topic
    qos = def.qos
  end

  return self.client:publish(topic, payload, qos)
end

--- 关闭平台（不太需要）
function MQTT:close()
  if self.client ~= nil then
    self.client:close()
    self.client = nil
  end
end

--- @return boolean 状态
function MQTT:ready()
  return self.client ~= nil and self.client:ready()
end

return MQTT
