--[[
  ME NETWORK READOUT
  CC: Tweaked + Advanced Peripherals

  Reads a real AE2 network through an ME Bridge and prints the
  numbers that matter to a monitor. The computer does not need to
  touch the controller -- everything is reached over wired modems.

  Every ME Bridge method returns "value, errorString". A failed call
  returns nil plus a message instead of throwing, so this script
  captures both and shows you the message rather than guessing.

  Layout picks the largest text scale that still fits and re-fits
  itself if monitor blocks are added or removed while running.

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
  energyLabel  = "AE",  -- AE2 reports AE, not FE
  debug        = true,  -- print every failed call to the computer terminal
}

-- Smallest layout the full readout needs, in characters.
local MIN_W, MIN_H = 26, 12

--==========================================================
-- COLOURS
-- Slots are powers of two, defined here so the script does not
-- depend on the colors/colours API tables existing.
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

-- Below MC 1.21.1 the peripheral type is "meBridge".
-- On 1.21.1 and above it is "me_bridge".
local bridge, bridgeType
if CONFIG.bridgeName then
  bridge = peripheral.wrap(CONFIG.bridgeName)
  bridgeType = bridge and peripheral.getType(CONFIG.bridgeName) or nil
else
  for _, t in ipairs({ "meBridge", "me_bridge" }) do
    local b = peripheral.find(t)
    if b then bridge, bridgeType = b, t break end
  end
end

--==========================================================
-- CALLING THE BRIDGE
--
-- AP methods are documented as:  method() -> value, err: string
-- A failure returns nil plus a message, it does NOT throw. So we
-- must capture both return values, and separately guard against a
-- genuine Lua error with pcall.
--==========================================================

local lastError = nil

local function call(name, ...)
  if not bridge then
    return nil, "no ME Bridge on the peripheral network"
  end

  local fn = bridge[name]
  if type(fn) ~= "function" then
    return nil, name .. " is not available in this AP version"
  end

  local ok, value, err = pcall(fn, ...)

  if not ok then
    -- the call threw; `value` holds the Lua error message
    return nil, name .. " threw: " .. tostring(value)
  end

  if value == nil then
    -- the documented failure path: nil + reason
    return nil, name .. ": " .. tostring(err or "returned nil with no reason")
  end

  return value
end

-- Convenience wrapper that records the reason a call failed.
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
-- CC accepts text scales from 0.5 to 5 in steps of 0.5. Walk them
-- from largest down and keep the first that fits the layout.
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
  ok = false,
  err = "connecting",
  energy = 0, energyMax = 0, usage = 0,
  hasItemStats = false, itemUsed = 0, itemTotal = 0,
  hasFluidStats = false, fluidUsed = 0, fluidTotal = 0,
  cpuTotal = 0, cpuBusy = 0,
  types = nil,
}

local pollCount = 0

local function poll()
  lastError = nil

  local energy, err = call("getEnergyStorage")
  if energy == nil then
    data.ok = false
    data.err = err or "unknown failure"
    if CONFIG.debug then print("[bridge] " .. data.err) end
    return
  end

  data.ok = true
  data.err = nil
  data.energy    = energy
  data.energyMax = get("getMaxEnergyStorage") or 0
  data.usage     = get("getEnergyUsage") or 0

  local iu = get("getUsedItemStorage")
  local it = get("getTotalItemStorage")
  data.hasItemStats = (iu ~= nil and it ~= nil and it > 0)
  data.itemUsed, data.itemTotal = iu or 0, it or 0

  local fu = get("getUsedFluidStorage")
  local ft = get("getTotalFluidStorage")
  data.hasFluidStats = (fu ~= nil and ft ~= nil and ft > 0)
  data.fluidUsed, data.fluidTotal = fu or 0, ft or 0

  local cpus = get("getCraftingCPUs")
  if type(cpus) == "table" then
    data.cpuTotal = #cpus
    local busy = 0
    for _, c in ipairs(cpus) do
      if c.isBusy then busy = busy + 1 end
    end
    data.cpuBusy = busy
  end

  pollCount = pollCount + 1
  if CONFIG.countTypes and (pollCount % CONFIG.typesEvery == 1) then
    local items = get("listItems")
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

-- Wraps a message across the remaining rows so long bridge errors
-- are readable instead of cut off at the edge.
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
  elseif data.cpuBusy > 0 then status, scol = "CRAFTING", YELLOW
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
  elseif y <= H then
    row(y, "Item cells", "unsupported", LIGHTGRAY, GRAY)
    y = y + 2
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
    row(y, "Crafting CPUs",
        string.format("%d / %d", data.cpuBusy, data.cpuTotal),
        LIGHTGRAY, data.cpuBusy > 0 and YELLOW or WHITE)
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
print("Bridge:  " .. (bridge and ("found as " .. tostring(bridgeType)) or "MISSING"))
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
    local ev = os.pullEvent()
    if ev == "monitor_resize" then
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