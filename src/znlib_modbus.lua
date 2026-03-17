--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2026-03-15
  描述： modbus-rtu
-------------------------------------------------------------------------------]]
local tag = "modbus"
local modbus = {}
modbus.__index = modbus

--异步转同步等待
local waiter = require("znlib_waiter"):new()

--线圈状态
modbus.COILS_ON = 0xFF00
modbus.COILS_OFF = 0x0000

--操作类型
modbus.READ_COILS = 0x01                       -- 读线圈状态
modbus.READ_DISCRETE_INPUTS = 0x02             -- 读离散输入状态
modbus.READ_HOLDING_REGISTERS = 0x03           -- 读保持寄存器
modbus.READ_INPUT_REGISTERS = 0x04             -- 读输入寄存器
modbus.WRITE_SINGLE_COIL = 0x05                -- 写单个线圈状态
modbus.WRITE_SINGLE_HOLDING_REGISTER = 0x06    -- 写单个保持寄存器
modbus.WRITE_MULTIPLE_HOLDING_REGISTERS = 0x10 -- 写多个保持寄存器
modbus.WRITE_MULTIPLE_COILS = 0x0F             -- 写多个线圈状态

---创建实例
---@param config table 串口配置
---@return boolean|table
function modbus:create(config)
  local obj = {
    cmd_data = {},                          --命令数据
    uart_initialized = false,               --初始化状态
    uart_id = config.uart_id,               --串口标识
    rs485_dir_gpio = config.rs485_dir_gpio, --485转换引脚
  }

  --设置元表
  setmetatable(obj, modbus)

  local result = uart.setup(
    config.uart_id,
    config.baud_rate,
    config.data_bits,
    config.stop_bits,
    config.parity_bits,
    config.byte_order,
    nil,
    config.rs485_dir_gpio,
    config.rs485_dir_rx_level
  )

  if result ~= 0 then
    znlib.show_log("串口 " .. config.uart_id .. " 初始化失败", tag, log.LOG_ERROR)
    obj:destroy()
    return false
  end

  local buf_start, buf_end = 0, 0         --接收缓冲游标指针
  local buf_size = config.buf_size        --接收缓冲大小
  local uart_buf = zbuff.create(buf_size) --接收缓冲区

  ---返回真实的索引(real-index)
  ---@param val number
  ---@return number
  local r_i = function (val)
    return val % buf_size
  end

  --处理数据
  uart.on(config.uart_id, "receive", function (id, len)
    if len < 1 then return end       --无数据
    if obj.cmd_data.wait_id < 1 then --无业务,作废
      uart.read(id, len)
    end

    --[[游标说明:
      1.buf_start: 数据开始位置,初始0
      2.buf_end: 数据结束位置,初始0,不包含在数据内
      3.buf_start = buf_end,数据为空
        buf_start < buf_end,数据为 buf_start -> buf_end
        buf_start > buf_end,数据为 buf_start -> buf_size - 1, 0 -> buf_end
      4.数据处理完毕后: buf_start = buf_end = 0, seek(0)
    --]]

    if buf_start == buf_end then
      --数据为空,重置游标
      buf_start, buf_end = 0, 0
      uart_buf:seek(0)
    else
      --移至末尾,准备写入
      uart_buf:seek(buf_end)
    end

    local cur_size = buf_size - buf_end --剩余空间
    if cur_size >= len then             --空间足够
      uart_buf:write(uart.read(id, len))
      if buf_end < buf_start then       --结束位置折返
        buf_end = uart_buf:used()
        if buf_end >= buf_start then    --数据覆盖
          buf_start = (buf_end + 1) % buf_size
        end
      else
        buf_end = uart_buf:used()
      end
    else --空间不足,分段处理
      if cur_size > 0 then
        uart_buf:write(uart.read(id, cur_size))
      end

      uart_buf:seek(0)                              --移至开头
      uart_buf:write(uart.read(id, len - cur_size)) --写入剩余
      buf_end = uart_buf:used()

      if buf_end >= buf_start then --数据覆盖
        buf_start = (buf_end + 1) % buf_size
      end
    end

    if isDebug then
      log.info(tag, "游标", buf_start, buf_end)
    end

    if buf_start == buf_end then return end --emtpy data
    local max = (buf_start < buf_end) and buf_end or (buf_end + buf_size)
    local idx = buf_start

    -----------------------------------------------------------------------------
    while idx < max do
      if obj.cmd_data.is_read then
        if max - idx < 5 then break end --数据不全:地址1 功能码1 数据量1 数据n 校验2
      elseif max - idx < 8 then         --数据不全:地址1 功能码1 地址2 数据2 校验2
        break
      end

      if uart_buf[r_i(idx)] ~= obj.cmd_data.slave_id or       --站地址匹配
          uart_buf[r_i(idx + 1)] ~= obj.cmd_data.op_type then --功能码匹配
        idx = idx + 1                                         --忽略不匹配
        buf_start = r_i(idx)                                  --更新开始游标
        goto continue
      end

      local dLen = 0
      if obj.cmd_data.is_read then
        dLen = uart_buf[r_i(idx + 2)] + idx + 2 --校验前位置
      else
        dLen = idx + 5                          --写操作的应答数据,定长 8 位
      end

      if dLen + 2 >= max then --数据未收完
        break
      end

      local tmp = ""
      for i = idx, dLen, 1 do
        tmp = tmp .. string.char(uart_buf[r_i(i)])
      end

      local crc = 0
      if obj.cmd_data.crc_order == uart.MSB then --大端
        crc = uart_buf[r_i(dLen + 1)] * 256 + uart_buf[r_i(dLen + 2)]
      else                                       --小端
        crc = uart_buf[r_i(dLen + 2)] * 256 + uart_buf[r_i(dLen + 1)]
      end

      if crc == crypto.crc16_modbus(tmp) then                                --校验通过
        local val = {}
        if obj.cmd_data.op_type == modbus.READ_HOLDING_REGISTERS or          --读保持寄存器
            obj.cmd_data.op_type == modbus.READ_INPUT_REGISTERS then         --读输入寄存器
          for i = idx + 3, dLen, 2 do
            table.insert(val, uart_buf[r_i(i)] * 256 + uart_buf[r_i(i + 1)]) --大端数据
          end
        elseif obj.cmd_data.op_type == modbus.READ_COILS or                  --读线圈状态
            obj.cmd_data.op_type == modbus.READ_DISCRETE_INPUTS then         --读离散输入状态
          for i = idx + 3, dLen, 1 do
            table.insert(val, uart_buf[r_i(i)])
          end
        end

        --返回数据
        waiter:wakeup(obj.cmd_data.wait_id, val)
      end

      idx = dLen + 3       --下一组索引
      buf_start = r_i(idx) --更新开始游标

      --跳转坐标
      ::continue::
    end
  end)

  --初始化完毕
  obj.uart_initialized = true
  znlib.show_log(utils.table_to_str(config), tag)
  return obj
end

---释放资源
function modbus:destroy()
  if not self then return end
  --invalid check

  if self.uart_initialized then
    self.uart_buf:free()
    uart.close(self.uart_id)
    uart.on(self.uart_id, "sent", nil)
    uart.on(self.uart_id, "receive", nil)
  end

  if self.rs485_dir_gpio then
    gpio.close(self.rs485_dir_gpio)
  end

  -- 销毁已创建的实例
  setmetatable(self, nil)
end

---读写数据
---@param rtu_cmd table 读写命令
---@return boolean 返回有效
---@return any|nil 返回数据
function modbus:execute(rtu_cmd)
  self.cmd_data.is_read = rtu_cmd.op_type < 0x05
  --读命令值1-4

  local data = ""
  if self.cmd_data.is_read then
    data = (string.format("%02x", rtu_cmd.slave_id) ..    --从站地址
      string.format("%02x", rtu_cmd.op_type) ..           --操作符
      string.format("%04x", rtu_cmd.start_addr) ..        --寄存器地址
      string.format("%04x", rtu_cmd.reg_count)):fromHex() --读取数量
  else                                                    --写数据
    if #rtu_cmd.reg_data < 1 then
      znlib.show_log("数据列表为空", tag, log.LOG_ERROR)
      return false
    end

    if rtu_cmd.op_type == modbus.WRITE_SINGLE_COIL or                   --写单个线圈状态
        rtu_cmd.op_type == modbus.WRITE_SINGLE_HOLDING_REGISTER then    --写单个保持寄存器
      data = (string.format("%02x", rtu_cmd.slave_id) ..                --从站地址
        string.format("%02x", rtu_cmd.op_type) ..                       --操作符
        string.format("%04x", rtu_cmd.start_addr) ..                    --寄存器地址
        string.format("%04x", rtu_cmd.reg_data[1])):fromHex()           --数据
    elseif rtu_cmd.op_type == modbus.WRITE_MULTIPLE_COILS or            --写多个线圈状态
        rtu_cmd.op_type == modbus.WRITE_MULTIPLE_HOLDING_REGISTERS then --写多个保持寄存器
      data = string.format("%02x", rtu_cmd.slave_id) ..                 --从站地址
          string.format("%02x", rtu_cmd.op_type) ..                     --操作符
          string.format("%04x", rtu_cmd.start_addr) ..                  --寄存器地址
          string.format("%04x", rtu_cmd.reg_count) ..                   --寄存器数量
          string.format("%02x", #rtu_cmd.reg_data * 2)                  --数据字节数

      for i = 1, #rtu_cmd.reg_data, 1 do
        data = data .. string.format("%04x", rtu_cmd.reg_data[i]) --数据
      end

      data = data:fromHex()
    end
  end

  if #data < 1 then
    znlib.show_log("不支持的操作类型", tag, log.LOG_ERROR)
    return false
  end

  --命令摘要
  self.cmd_data.wait_id = znlib.make_id()
  self.cmd_data.op_type = rtu_cmd.op_type
  self.cmd_data.slave_id = rtu_cmd.slave_id
  self.cmd_data.crc_order = rtu_cmd.crc_order

  local crc = crypto.crc16_modbus(data)
  if rtu_cmd.crc_order == uart.MSB then --大端
    data = data .. string.char((crc >> 8) & 0xFF, crc & 0xFF)
  else                                  --小端
    data = data .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
  end

  --发送数据
  uart.write(self.uart_id, data)

  --等待结果
  local ok, dt = waiter:wait_for(self.cmd_data.wait_id, rtu_cmd.timeout)
  self.cmd_data.wait_id = 0
  return ok, dt
end

return modbus

--[[-----------------------------------------------------------------------------
local modbus = require("znlib_modbus")

local config = {
  uart_id = 1,               --串口ID
  baud_rate = 4800,          --波特率
  data_bits = 8,             --数据位
  stop_bits = 1,             --停止位
  parity_bits = uart.None,   --校验位
  byte_order = uart.LSB,     --字节顺序
  buf_size = 64,             --接收缓冲大小
  --rs485_dir_gpio = 25,     --RS485 方向转换 GPIO 引脚
  --rs485_dir_rx_level = 0   --RS485 接收方向电平：0 为低电平，1 为高电平
}

local rtu = modbus:create(config)
if not rtu then
  return
end

local read = {
  op_type = modbus.READ_HOLDING_REGISTERS,
  slave_id = 1,           --从站标识
  start_addr = 1,         --开始地址
  reg_count = 3,          --读取数量
  crc_order = uart.LSB,   --字节顺序
  timeout = 1 * 1000      --等待超时
}

local write = {
  op_type = modbus.WRITE_MULTIPLE_HOLDING_REGISTERS,
  slave_id = 1,          --从站标识
  start_addr = 1,        --开始地址
  reg_count = 2,         --寄存器数
  reg_data = { 12, 34 }, --待写入数据
  crc_order = uart.LSB,  --字节顺序
  timeout = 1 * 1000     --等待超时
}

while true do
  local ok, dt = rtu:execute(read)
  if ok then
    log.info("demo", utils.table_to_str(dt))
  else
    log.info("demo", "读取超时")
  end

  ok, dt = rtu:execute(write)
  if ok then
    log.info("demo", "写入成功")
  else
    log.info("demo", "写入超时")
  end
  sys.wait(1000)
end
-------------------------------------------------------------------------------]]
