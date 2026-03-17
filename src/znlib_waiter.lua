--[[-----------------------------------------------------------------------------
  作者： dmzn@163.com 2026-03-15
  描述： 异步转同步
-------------------------------------------------------------------------------]]
local tag = "waiter"
local waiter = {}
waiter.__index = waiter

---创建新实例
function waiter:new()
  local obj = { tasks = {} }
  setmetatable(obj, waiter)
  return obj
end

---等待某个任务被唤醒或超时
---@param task number 任务标识
---@param timeout number 超时时间(ms)
---@param data any 任务数据
---@return boolean 超时返回false
---@return any topic内容
function waiter:wait_for(task, timeout, data)
  if data ~= nil then
    self.tasks[task] = data
  end

  local ok, dt = sys.waitUntil("znlib_waiter_" .. task, timeout)
  self.tasks[task] = nil
  return ok, dt
end

---唤醒某个等待任务
---@param task number|function 任务标识
---@param data any 任务数据
function waiter:wakeup(task, data)
  local id = 0
  if type(task) == "function" then
    for tk, dt in pairs(self.tasks) do
      if task(dt) then
        id = tk
        break
      end
    end

    if id < 1 then
      znlib.show_log("没有匹配到任务编号", tag)
      return
    end
  else
    id = task
  end

  sys.publish("znlib_waiter_" .. id, data)
end

return waiter

--[[-----------------------------------------------------------------------------
local task = znlib.make_id()
local waiter = require("znlib_waiter"):new()

local ok, dt = waiter:wait_for(task, 2000, { 1, 2 })
--等待2秒,传入任务数据
if ok then
  log.info("demo", utils.table_to_str(dt))
else
  log.info("demo", "任务超时")
end

waiter:wakeup(function (data) return data[1] ~= nil end, { "a", "b" })
--匹配任务数据,成功后唤醒并返回数据
-------------------------------------------------------------------------------]]
