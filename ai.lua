--[[
  ME NETWORK READOUT
  CC: Tweaked + Advanced Peripherals

  Works with both ME Bridge APIs:

    legacy (AP 0.7, MC 1.20.1 and older)
      getEnergyStorage / getMaxEnergyStorage / getCraftingCPUs
      listItems()

    modern (AP 0.8, and 0.7 on MC 1.21.1+)
      getStoredEnergy / getEnergyCapacity / getCraftingTasks
      listItems({})   -- now takes a filter
      isConnected() / isOnline()

  The script detects which one the bridge exposes and calls the
  matching names. Every call returns "value, errorString" on
  failure rather than throwing, so both are captured.

  Ctrl+T to stop.
]]

--==========================================================
-- CONFIG
--==========================================================

local CONFIG = {
  monitorName  = nil,   -- nil = auto-detect, or e.g. "monitor_2"
  bridgeName   = nil,   -- nil = auto-detect, or e.g. "meBridge_0"
  pollInterval = 3,     -- seconds between network reads
  countTypes   = true,  -- false on very large networks (listItems is slow)
  typesEvery   = 5,     -- refresh the type count every N polls
  energyLabel  = "AE",  -- AE2 reports AE
  debug        = true,  -- print failed calls to the computer terminal
}

local MIN_W, MIN_H = 26, 12

--==========================================================
-- COLOURS  (slots are powers of two)
--==========================================================

local WHITE, ORANGE, YELLOW, LIME  = 1, 2, 16, 32
local GRAY, LIGHTGRAY, RED, BLACK  = 128, 256, 16384, 32768

--==========================================================
-- PERIPHERALS
--==========================================================

local mon = CONFIG.monitorName and peripheral.wrap(CONFIG.monitorName)
             or peripheral.find("monitor")
if not mon then
  error("No monitor found. Check the modems on both ends are switched on (red).", 0)
end

local bridge, bridgeType
if CONFIG.bridgeName then
  bridge = peripheral.wrap(CONFIG.bridgeName)
  bridgeType = bridge and peripheral.getType(CONFIG.bridgeName) or nil
else
  -- "meBridge" below MC 1.21.1, "me_bridge" on 1.21.1 and above
  for _, t in ipairs({ "meBridge", "me_bridge" }) do
    local b = peripheral.find(t)
    if b then bridge, bridgeType = b, t break end
  end
end

if not bridge then
  error("No ME Bridge on the peripheral network. Switch the modems on (red).", 0)
end

--==========================================================
-- API DETECTION
--==========================================================

local has = function(name) return type(bridge[name]) == "function" end

local API, M

if has("getStoredEnergy") then
  API = "0.8"
  M = {
    energy      = "getStoredEnergy",
    energyMax   = "getEnergyCapacity",
    usage       = "getEnergyUsage",
    itemUsed    = "getUsedItemStorage",
    itemTotal   = "getTotalItemStorage",
    fluidUsed   = "getUsedFluidStorage",
    fluidTotal  = "getTotalFluidStorage",
    listItems   = "listItems",
    listArgs    = {},          -- modern listItems needs a filter table
    tasks       = "getCraftingTasks",
    cpus        = nil,
  }
elseif has("getEnergyStorage") then
  API = "0.7"
  M = {
    energy      = "getEnergyStorage",
    energyMax   = "getMaxEnergyStorage",
    usage       = "getEnergyUsage",
    itemUsed    = "getUsedItemStorage",
    itemTotal   = "getTotalItemStorage",
    fluidUsed   = "getUsedFluidStorage",
    fluidTotal  = "getTotalFluidStorage",
    listItems   = "listItems",
    listArgs    = nil,         -- legacy listItems takes no argument
    tasks       = nil,
    cpus        = "getCraftingCPUs",
  }
else
  error("Bridge exposes neither getStoredEnergy nor getEnergyStorage. "
        .. "Run the probe script to list its methods.", 0)
end

--==========================================================
-- CALLING THE BRIDGE
--==========================================================

local lastError = nil

local function call(name, ...)
  if not name then return nil, "not supported by this API" end
  local fn = bridge[name]
  if type(fn) ~= "function" then
    return nil, name .. " is not available in this AP version"
  end
  local ok, value, err = pcall(fn, ...)
  if not ok then
    return nil, name .. " threw: " .. tostring(value)
  end
  if value == nil then
    return nil, name .. ": " .. tostring(err or "returned nil with no reason")
  end
  return value
end

local function get(name, ...)
  local value, err = call(name, ...)
  if value == nil and err then
    lastError = err
    if CONFIG.debug then print("[bridge] " .. err) end
  end
  return value
end

--==========================================================
-- SCALING
--==========================================================

local SCALES = { 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5 }
local W, H, SCALE

local function fitScale()
  for _, s in ipairs(SCALES) do
    mon.setTextScale(s)
    local w, h = mon.getSize()
    if w >= MIN_W and h >= MIN_H then
      SCALE, W, H = s, w, h
      return
    end
  end
  mon.setTextScale(0.5)
  SCALE = 0.5
  W, H = mon.getSize()
end

--==========================================================
-- DATA
--==========================================================

local data = {
  ok = false, err = "connecting",
  energy = 0, energyMax = 0, usage = 0,
  hasItemStats = false, itemUsed = 0, itemTotal = 0,
  hasFluidStats = false, fluidUsed = 0, fluidTotal = 0,
  jobs = 0, jobLabel = "Crafting", jobTotal = nil,
  types = nil,
}

local pollCount = 0

local function poll()
  lastError = nil

  -- The modern API can be asked directly whether the grid is up.
  if has("isOnline") then
    local ok, err = call("isOnline")
    if ok == nil then
      data.ok, data.err = false, err or "isOnline failed"
      if CONFIG.debug then print("[bridge] " .. data.err) end
      return
    end
    if ok == false then
      local conn = call("isConnected")
      data.ok = false
      data.err = (conn == false)
        and "bridge is not connected to a grid"
        or  "grid is offline (no power?)"
      return
    end
  end

  local energy, err = call(M.energy)
  if energy == nil then
    data.ok, data.err = false, err or "unknown failure"
    if CONFIG.debug then print("[bridge] " .. data.err) end
    return
  end

  data.ok, data.err = true, nil
  data.energy    = energy
  data.energyMax = get(M.energyMax) or 0
  data.usage     = get(M.usage) or 0

  local iu, it = get(M.itemUsed), get(M.itemTotal)
  data.hasItemStats = (iu ~= nil and it ~= nil and it > 0)
  data.itemUsed, data.itemTotal = iu or 0, it or 0

  local fu, ft = get(M.fluidUsed), get(M.fluidTotal)
  data.hasFluidStats = (fu ~= nil and ft ~= nil and ft > 0)
  data.fluidUsed, data.fluidTotal = fu or 0, ft or 0

  -- Crafting: the modern API lists running tasks, the legacy one
  -- lists CPUs and marks which are busy.
  if M.tasks then
    local tasks = get(M.tasks)
    data.jobs     = (type(tasks) == "table") and #tasks or 0
    data.jobLabel = "Crafting jobs"
    data.jobTotal = nil
  elseif M.cpus then
    local cpus = get(M.cpus)
    if type(cpus) == "table" then
      local busy = 0
      for _, c in ipairs(cpus) do
        if c.isBusy then busy = busy + 1 end
      end
      data.jobs, data.jobTotal = busy, #cpus
    end
    data.jobLabel = "Crafting CPUs"
  end

  pollCount = pollCount + 1
  if CONFIG.countTypes and (pollCount % CONFIG.typesEvery == 1) then
    local items
    if M.listArgs then items = get(M.listItems, M.listArgs)
    else items = get(M.listItems) end
    if type(items) == "table" then data.types = #items end
  end
end

--==========================================================
-- FORMATTING
--==========================================================

local function fmt(n)
  n = tonumber(n) or 0
  local a = math.abs(n)
  if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
  if a >= 1e9  then return string.format("%.2fG", n / 1e9)  end
  if a >= 1e6  then return string.format("%.2fM", n / 1e6)  end
  if a >= 1e3  then return string.format("%.1fk", n / 1e3)  end
  return string.format("%d", n)
end

local function pct(used, total)
  if not total or total <= 0 then return 0 end
  return math.min(1, used / total)
end

local function loadColour(p)
  if p >= 0.9 then return RED end
  if p >= 0.7 then return YELLOW end
  return LIME
end

--==========================================================
-- DRAWING
--==========================================================

local function at(x, y, text, fg, bg)
  mon.setCursorPos(x, y)
  mon.setTextColour(fg or WHITE)
  mon.setBackgroundColour(bg or BLACK)
  mon.write(text)
end

local function row(y, label, value, lc, vc)
  local pad = W - 2 - #label - #value
  if pad < 1 then
    at(2, y, (label .. " " .. value):sub(1, W - 2), lc)
    return
  end
  at(2, y, label, lc or LIGHTGRAY)
  at(2 + #label, y, string.rep(" ", pad), WHITE)
  at(W - #value, y, value, vc or WHITE)
end

local function bar(y, p, colour)
  local width = W - 2
  local filled = math.floor(width * p + 0.5)
  mon.setCursorPos(2, y)
  mon.setBackgroundColour(colour)
  mon.write(string.rep(" ", filled))
  mon.setBackgroundColour(GRAY)
  mon.write(string.rep(" ", width - filled))
  mon.setBackgroundColour(BLACK)
end

local function rule(y)
  at(2, y, string.rep("-", W - 2), GRAY)
end

local function wrapText(y, text, colour)
  local width = W - 2
  local i = 1
  while i <= #text and y <= H do
    at(2, y, text:sub(i, i + width - 1), colour)
    i = i + width
    y = y + 1
  end
  return y
end

local function render()
  mon.setBackgroundColour(BLACK)
  mon.clear()

  local y = 1

  local status, scol
  if not data.ok then status, scol = "OFFLINE", RED
  elseif data.jobs > 0 then status, scol = "CRAFTING", YELLOW
  else status, scol = "ONLINE", LIME end
  row(y, "ME NETWORK", status, ORANGE, scol)
  y = y + 1

  if y <= H then rule(y); y = y + 1 end

  if not data.ok then
    y = y + 1
    wrapText(y, data.err or "unknown failure", RED)
    return
  end

  if y + 2 <= H then
    local p = pct(data.energy, data.energyMax)
    row(y, "Energy", fmt(data.energy) .. " " .. CONFIG.energyLabel)
    bar(y + 1, p, loadColour(1 - p))
    row(y + 2, "Draw", fmt(data.usage) .. " " .. CONFIG.energyLabel .. "/t")
    y = y + 4
  end

  if data.hasItemStats and y + 2 <= H then
    local p = pct(data.itemUsed, data.itemTotal)
    row(y, "Item cells", string.format("%d%%", math.floor(p * 100 + 0.5)),
        LIGHTGRAY, loadColour(p))
    bar(y + 1, p, loadColour(p))
    row(y + 2, "Bytes", fmt(data.itemUsed) .. " / " .. fmt(data.itemTotal))
    y = y + 4
  end

  if data.hasFluidStats and y + 2 <= H then
    local p = pct(data.fluidUsed, data.fluidTotal)
    row(y, "Fluid cells", string.format("%d%%", math.floor(p * 100 + 0.5)),
        LIGHTGRAY, loadColour(p))
    bar(y + 1, p, loadColour(p))
    row(y + 2, "mB", fmt(data.fluidUsed) .. " / " .. fmt(data.fluidTotal))
    y = y + 4
  end

  if y <= H then rule(y); y = y + 1 end
  if y <= H then
    local v = data.jobTotal
      and string.format("%d / %d", data.jobs, data.jobTotal)
      or  tostring(data.jobs)
    row(y, data.jobLabel, v, LIGHTGRAY, data.jobs > 0 and YELLOW or WHITE)
    y = y + 1
  end
  if data.types and y <= H then
    row(y, "Item types", fmt(data.types))
    y = y + 1
  end
  if lastError and y <= H then
    at(2, y, lastError:sub(1, W - 2), GRAY)
  end
end

--==========================================================
-- RUN
--==========================================================

mon.setPaletteColour(ORANGE, 0xf0a32a)
fitScale()

term.clear()
term.setCursorPos(1, 1)
print("ME Network Readout")
print("Monitor: " .. W .. "x" .. H .. " at scale " .. SCALE)
print("Bridge:  " .. tostring(bridgeType) .. "  (API " .. API .. ")")
print("Ctrl+T to stop.")
print("")

local function pollLoop()
  while true do
    poll()
    render()
    sleep(CONFIG.pollInterval)
  end
end

local function resizeLoop()
  while true do
    if os.pullEvent() == "monitor_resize" then
      fitScale()
      render()
    end
  end
end

local ok, err = pcall(function()
  parallel.waitForAny(pollLoop, resizeLoop)
end)

mon.setPaletteColour(ORANGE, 0xF2B233)
mon.setBackgroundColour(BLACK)
mon.setTextColour(WHITE)
mon.clear()
mon.setCursorPos(1, 1)

if not ok then printError(err) end