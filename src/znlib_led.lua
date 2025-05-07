--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2025-05-07
  描述： 板载LED配置
-------------------------------------------------------------------------------]]
local tag = "led"
local led = {}
local options = {}

--- LED初始化
function led.init()
  -- 加载配置
  options = require("znlib_cfg").load_default(tag, { enable = false })
  if not options.enable then
    return
  end

  if options.pins == nil then
    log.info(tag, "未配置引脚(gpio)参数")
  end

  -- 读取GPIO配置表
  for k, v in pairs(options.pins) do
    log.info(tag, k, utils.table_to_str(v))
    gpio.setup(v.pin, v.mode, v.init)
  end
end

---点亮LED
---@param id string 名称
function led.on(id)
  local pin = options.pins[id]
  if pin ~= nil then
    gpio.set(pin.pin, pin.on)
  end
end

---关闭LED
---@param id string 名称
function led.off(id)
  local pin = options.pins[id]
  if pin ~= nil then
    gpio.set(pin.pin, pin.off)
  end
end

-- 启动
led.init()

--状态切换
if options.enable then
  local led_name = "net"
  if options.pins[led_name] then --网络灯
    sys.subscribe("IP_READY", function ()
      led.on(led_name)
    end)

    sys.subscribe("IP_LOSE", function ()
      led.off(led_name)
    end)
  end

  led_name = "gps"
  if options.pins[led_name] and libgnss then --gps
    sys.subscribe("GNSS_STATE", function (event, ticks)
      -- event取值有
      -- FIXED 定位成功
      -- LOSE  定位丢失
      -- ticks是事件发生的时间,一般可以忽略

      if libgnss.isFix() then
        led.on(led_name)
      else
        led.off(led_name)
      end
    end)
  end

  led_name = "ready"
  if options.pins[led_name] then --运行灯
    led.on(led_name)
  end
end


return led
