--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2025-05-07
  描述： 适用于合宙4G物联网模块的基础库
-------------------------------------------------------------------------------]]
local tag = "znlib"
local znlib = {}

Status_IP_Ready = "IP_READY"
--luat发送：网络就绪

Status_Net_Ready = "net_ready"
--系统消息：网络就位

Status_Log = "print_log"
--系统消息: 打印日志

Status_low_power = "low_power"
--系统消息: 进入低功耗

Status_NTP_Ready = "NTP_UPDATE";
--系统消息: 时间同步完毕

Status_OTA_Update = "ota_update"
--系统消息：OTA在线升级

Status_Mqtt_Connected = "mqtt_conn"
--系统消息：mqtt连接成功

Status_Mqtt_SubData = "mqtt_sub"
--系统消息: mqtt收到订阅数据

Status_Mqtt_PubData = "mqtt_pub"
--系统消息: mqtt发布数据

device_id = mcu.unique_id():toHex()
--设备ID,联网后会更新

--全局消息管理
Event = require("znlib_event")

--通过mqtt发送日志
EventType_MQTT_LOG = "mqtt_log"

local pm_a, pm_b, pm_reason = pm.lastReson()
--开机原因,用于判断是从休眠模块开机,还是电源/复位开机

local options = {
  up_log = 1800,           --上行日志超时(秒)
  ota = {
    enable = true,         --ota启用
    update = 3600000 * 24, --更新间隔(毫秒)
  },
  low_power = {
    enable = true,      --低功耗启用
    start = "22:00:00", --时间: 低功耗开启,
    exit = "07:00:00",  --时间: 低功耗退出
  },
  ntp = {
    enable = true,        --ntp启用
    fresh = 3600000 * 24, --刷新间隔(毫秒)
    retry = 3600000       --异常后重试间隔(毫秒)
  }
}

---------------------------------------------------------------------------------
--远程日志超时计时
local remote_log_init = 0

---设置远程日志计时
---@param val number
function znlib.remote_log_set(val)
  remote_log_init = val
end

---本地输出日志,或上行至服务器
---@param event string 日志
---@param remote boolean|nil 是否上行
function znlib.show_log(event, remote, level)
  if (#event) < 1 then -- empty
    return
  end

  level = (level ~= nil) and level or log.LOG_INFO               --默认: info
  remote = (remote ~= nil) and remote or false                   --默认: 仅本地
  remote = remote and (remote_log_init > 0) and
      (os.difftime(os.time(), remote_log_init) < options.up_log) --10分钟内有效

  if remote_log_init > 0 and (not remote) then
    remote_log_init = 0
  end

  if level == log.LOG_INFO then
    log.info(event)
  end

  if level == log.LOG_WARN then
    log.warn(event)
  end

  if level == log.LOG_ERROR then
    log.error(event)
  end

  if remote then --mqtt
    Event:trigger_callback(EventType_MQTT_LOG, event)
  end
end

---------------------------------------------------------------------------------
---低功耗唤醒
---@return boolean
function znlib.low_power_awake()
  --pm_a: 0-上电/复位开机, 1-RTC开机, 2-WakeupIn/Pad/IO开机, 3-未知原因
  --pm_b: 0-普通开机(上电/复位),3-深睡眠开机,4-休眠开机
  if pm_a == 1 and pm_b == 3 then --深度睡眠醒来后,重启系统
    --mobile.flymode(0, false)      --退出飞行模式
    rtos.reboot()
    do return true end
  end

  return false
end

--[[
  date: 2025-05-07
  desc: 检查是否进入低功耗模式
--]]
function znlib.low_power_check()
  if pm_reason == 0 then
    log.info(tag, "PM: powerkey开机")
  elseif pm_reason == 1 then
    log.info(tag, "PM: 充电或者AT指令下载完成后开机")
  elseif pm_reason == 2 then
    log.info(tag, "PM: 闹钟开机")
  elseif pm_reason == 3 then
    log.info(tag, "PM: 软件重启")
  elseif pm_reason == 4 then
    log.info(tag, "PM: 未知原因")
  elseif pm_reason == 5 then
    log.info(tag, "PM: RESET键")
  elseif pm_reason == 6 then
    log.info(tag, "PM: 异常重启")
  elseif pm_reason == 7 then
    log.info(tag, "PM: 工具控制重启")
  elseif pm_reason == 8 then
    log.info(tag, "PM: 内部看门狗重启")
  elseif pm_reason == 9 then
    log.info(tag, "PM: 外部重启")
  elseif pm_reason == 10 then
    log.info(tag, "PM: 充电开机")
  end

  if not options.low_power.enable then --不启用
    return
  end

  --等待时间同步完成
  sys.waitUntil(Status_NTP_Ready)
  log.info(tag, "PM: 开始低功耗计时")

  --低功耗开启
  local lp_enabled = true
  --低功耗开启
  local l_h, l_m, l_s = options.low_power.start:match("(%d+):(%d+):(%d+)")
  --低功耗退出
  local e_h, e_m, e_s = options.low_power.exit:match("(%d+):(%d+):(%d+)")

  while true do
    ::continue::                                             --跳转坐标
    local ret, keep = sys.waitUntil(Status_low_power, 60000) --每1分钟
    if ret then                                              --低功耗开关
      lp_enabled = (keep > 0) and true or false
      if lp_enabled then
        log.info(tag, "PM: 低功耗已启用")
      else
        log.info(tag, "PM: 低功耗已关闭")
      end
    end

    if not lp_enabled then --low-powser disabled
      goto continue
    end

    if not ret then                 --超时: 没有服务器指令
      local cur = os.time()         --当前时间
      local dt = os.date("*t", cur) --拆分
      local l_in = os.time({        --开启时间
        year = dt.year,
        month = dt.month,
        day = dt.day,
        hour = l_h,
        min = l_m,
        sec = l_s
      }) - 3600 * 8

      local l_out = os.time({ --退出时间
        year = dt.year,
        month = dt.month,
        day = dt.day,
        hour = e_h,
        min = e_m,
        sec = e_s
      }) - 3600 * 8

      if l_in > l_out then --跨天退出
        dt = os.date("*t", cur + 24 * 3600);
        l_out = os.time({
          year = dt.year,
          month = dt.month,
          day = dt.day,
          hour = e_h,
          min = e_m,
          sec = e_s
        }) - 3600 * 8
      end

      --[[log.info("PM: 计时", os.date("%y-%m-%d %H:%M:%S", cur),
            os.date("%y-%m-%d %H:%M:%S", l_in),
            os.date("%y-%m-%d %H:%M:%S", l_out))
          --]]

      if (cur < l_in) or (cur > l_out) then --未到时间,已超时
        goto continue
      end

      keep = os.difftime(l_out, cur) --距离退出的秒数
    end

    log.info("PM: 进入低功耗模,keep ", keep)
    sys.wait(2000) --wait remote log

    --进入飞行模式
    mobile.flymode(0, true)

    --如果是插着USB测试，需要关闭USB
    pm.power(pm.USB, false)

    --关闭GPS电源
    pm.power(pm.GPS, false)

    --关闭GPS有源天线电源
    pm.power(pm.GPS_ANT, false)

    -- id = 0 或者 id = 1 是, 最大休眠时长是2.5小时
    -- id >= 2是, 最大休眠时长是740小时
    pm.dtimerStart(2, keep * 1000)

    --[[
      IDLE   正常运行,就是无休眠
      LIGHT  轻休眠, CPU停止, RAM保持, 外设保持, 可中断唤醒. 部分型号支持从休眠处继续运行
      DEEP   深休眠, CPU停止, RAM掉电, 仅特殊引脚保持的休眠前的电平, 大部分管脚不能唤醒设备.
      HIB    彻底休眠, CPU停止, RAM掉电, 仅复位/特殊唤醒管脚可唤醒设备.
    --]]
    pm.request(pm.DEEP)
  end
end

---------------------------------------------------------------------------------
--[[
  date: 2025-05-07
  desc: 联网
--]]
function znlib.conn_net()
  -----------------------------
  -- 统一联网函数
  ----------------------------
  if wlan and wlan.connect then
    -- wifi
    local ssid = "ssid"
    local password = "pwd"
    log.info(tag, ssid, password)

    -- TODO 改成自动配网
    -- LED = gpio.setup(12, 0, gpio.PULLUP)
    wlan.init()
    wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
    device_id = wlan.getMac()
    wlan.connect(ssid, password, 1)
  elseif mobile then
    -- Air780E/Air600E系列
    --mobile.simid(2) -- 自动切换SIM卡
    -- LED = gpio.setup(27, 0, gpio.PULLUP)
    device_id = mobile.imei()
  elseif w5500 then
    -- w5500 以太网, 当前仅Air105支持
    w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
    w5500.config() --默认是DHCP模式
    w5500.bind(socket.ETH0)
    -- LED = gpio.setup(62, 0, gpio.PULLUP)
  elseif socket or mqtt then
    -- 适配的socket库也OK
    -- 没有其他操作, 单纯给个注释说明
  else
    -- 其他不认识的bsp, 循环提示一下吧
    while 1 do
      sys.wait(1000)
      log.info(tag, "本bsp可能未适配网络层, 请查证")
    end
  end

  log.info(tag, "联网中,请稍后...")
  sys.waitUntil(Status_IP_Ready)
  sys.publish(Status_Net_Ready, device_id)
end

---------------------------------------------------------------------------------
--[[
  date: 2025-05-07
  desc: 在线更新时间

  对于Cat.1模块, 移动/电信卡,通常会下发基站时间,那么sntp就不是必要的
  联通卡通常不会下发, 就需要sntp了
  sntp内置了几个常用的ntp服务器, 也支持自选服务器
--]]
function znlib.online_ntp()
  if not options.ntp.enable then return end
  sys.waitUntil(Status_Net_Ready)
  sys.wait(1000)

  while true do
    -- 使用内置的ntp服务器地址, 包括阿里ntp
    log.info(tag, "NTP: 开始同步时间")
    socket.sntp()

    -- 通常只需要几百毫秒就能成功
    local ret = sys.waitUntil(Status_NTP_Ready, 5000)
    if ret then
      log.info(tag, "NTP: 时间同步成功 " .. os.date("%Y-%m-%d %H:%M:%S"))
      --每天一次
      sys.wait(options.ntp.fresh)
    else
      log.info(tag, "NTP: 时间同步失败")
      sys.wait(options.ntp.retry) -- 1小时后重试
    end
  end
end

---------------------------------------------------------------------------------
local ota_opts = {}
local function ota_cb(ret)
  if ret == 0 then
    log.info("OTA: 下载成功,升级中...", true)
    rtos.reboot()
  elseif ret == 1 then
    znlib.show_log("OTA: 连接失败,请检查url或服务器配置(是否为内网)", true)
  elseif ret == 2 then
    znlib.show_log("OTA: url错误")
  elseif ret == 3 then
    znlib.show_log("OTA: 服务器断开,检查服务器白名单配置", true)
  elseif ret == 4 then
    znlib.show_log("OTA: 接收报文错误,检查模块固件或升级包内文件是否正常", true)
  elseif ret == 5 then
    znlib.show_log("OTA: 版本号错误(xxx.yyy.zzz)", true)
  else
    znlib.show_log("OTA: 未定义错误 " .. tostring(ret), true)
  end
end

-- 使用iot平台进行升级
function znlib.ota_online()
  if not options.ota.enable then return end
  local libfota2 = require("libfota2")
  sys.waitUntil(Status_Net_Ready)

  local first = true
  while true do
    if first then --启动时检查1次
      first = false
    else
      sys.waitUntil(Status_OTA_Update, options.ota.update) --默认每天1检
    end

    znlib.show_log("OTA: 开始新版本确认", true)
    sys.wait(500)
    libfota2.request(ota_cb, ota_opts)
  end
end

---------------------------------------------------------------------------------
--加载配置
options = require("znlib_cfg").load_default(tag, options)
log.info(tag, "ota", utils.table_to_str(options.ota))
log.info(tag, "ntp", utils.table_to_str(options.ntp))
log.info(tag, "low_power", utils.table_to_str(options.low_power))

return znlib
