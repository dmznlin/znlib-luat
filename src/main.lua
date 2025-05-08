--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2025-04-28
  描述： 主程序
-------------------------------------------------------------------------------]]
PROJECT = "iot-4g"
VERSION = "1.0.1"
-- luatools needs

PRODUCT_KEY = ""
--在线升级

_G.isDebug = true
--true: 调试模式开
log.setLevel("INFO")

_G.sys = require("sys")           --standard
_G.sysplus = require("sysplus")   --mqtt needs
_G.libfota2 = require("libfota2") --ota needs

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
  pm.power(pm.PWK_MODE, false)
end

sys.taskInit(function ()
  --看门狗：3秒一喂，9秒超时
  wdt.init(9000)
  sys.timerLoopStart(wdt.feed, 3000)
end)

---------------------------------------------------------------------------------
_G.utils = require("znlib_utils") --global utils
_G.znlib = require("znlib")       --common lib

--休眠唤醒后,重启系统
if znlib.low_power_awake() then return end

--开始启动业务
log.info(string.format("启动中，系统:%s 内核:%s 标识:%s", VERSION, rtos.version(), device_id))

--板载指示灯
_G.led = require("znlib_led")

sys.taskInit(function ()
  --开始联网
  znlib.conn_net()
end)

sys.taskInit(function ()
  --时钟同步
  znlib.online_ntp()
end)

sys.taskInit(function ()
  --定时休眠
  znlib.low_power_check()
end)

sys.taskInit(function ()
  --在线升级
  znlib.ota_online()
end)

--代码结束
sys.run()
