--[[
  ME NETWORK READOUT
  CC: Tweaked + Advanced Peripherals

  Reads a real AE2 network through an ME Bridge and prints the
  numbers that matter to a monitor. The computer does not need to
  touch the controller -- everything is reached over wired modems.

  The layout picks the largest text scale that still fits, and
  re-fits itself if you add or remove monitor blocks while running.

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
  energyLabel  = "FE",  -- older builds report AE, newer report FE
}

-- Smallest layout the full readout needs, in characters.
local MIN_W, MIN_H = 26, 12

--==========================================================
-- COLOURS
-- Slots are powers of two. Defined here so the script does not
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

local bridge = CONFIG.bridgeName and peripheral.wrap(CONFIG.bridgeName)
                or peripheral.find("meBridge")

--==========================================================
-- SCALING
-- CC accepts text scales from 0.5 to 5 in steps of 0.5. Walk them
-- from largest down and keep the first that fits the layout, so a
-- big monitor gets big text instead of a wall of tiny characters.
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
  -- Monitor is too small for the full layout. Use the smallest text
  -- and let the renderer drop sections it cannot fit.
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
  itemUsed = 0, itemTotal = 0,
  fluidUsed = 0, fluidTotal = 0,
  cpuTotal = 0, cpuBusy = 0,
  types = nil,
}

local function call(name, ...)
  if not bridge or type(bridge[name]) ~= "function" then return nil end
  local ok, res = pcall(bridge[name], ...)
  if ok then return res end
  return nil
end

local pollCount = 0

local function poll()
  if not bridge then
    data.ok, data.err = false, "no ME Bridge on the network"
    return
  end

  local e = call("getEnergyStorage")
  if e == nil then
    data.ok, data.err = false, "bridge has no channel"
    return
  end

  data.ok        = true
  data.energy    = e or 0
  data.energyMax = call("getMaxEnergyStorage") or 0
  data.usage     = call("getEnergyUsage") or call("getAvgPowerUsage") or 0

  data.itemUsed   = call("getUsedItemStorage")   or 0
  data.itemTotal  = call("getTotalItemStorage")  or 0
  data.fluidUsed  = call("getUsedFluidStorage")  or 0
  data.fluidTotal = call("getTotalFluidStorage") or 0

  local cpus = call("getCraftingCPUs")
  if type(cpus) == "table" then
    data.cpuTotal = #cpus
    local busy = 0
    for _, c in ipairs(cpus) do
      if c.isBusy or c.busy then busy = busy + 1 end
    end
    data.cpuBusy = busy
  end

  pollCount = pollCount + 1
  if CONFIG.countTypes and (pollCount % CONFIG.typesEvery == 1) then
    local items = call("listItems")
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

-- Writes a label on the left and a value on the right of the same row,
-- padding the middle so old text is always cleared.
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

local function render()
  mon.setBackgroundColour(BLACK)
  mon.clear()

  local y = 1

  -- header
  local status, scol
  if not data.ok then status, scol = "OFFLINE", RED
  elseif data.cpuBusy > 0 then status, scol = "CRAFTING", YELLOW
  else status, scol = "ONLINE", LIME end
  row(y, "ME NETWORK", status, ORANGE, scol)
  y = y + 1

  if y <= H then rule(y); y = y + 1 end

  if not data.ok then
    if y <= H then at(2, y + 1, data.err:sub(1, W - 2), RED) end
    return
  end

  -- energy
  if y + 2 <= H then
    local p = pct(data.energy, data.energyMax)
    row(y, "Energy", fmt(data.energy) .. " " .. CONFIG.energyLabel)
    bar(y + 1, p, loadColour(1 - p))
    row(y + 2, "Draw", fmt(data.usage) .. " " .. CONFIG.energyLabel .. "/t")
    y = y + 4
  end

  -- item cells
  if y + 2 <= H then
    local p = pct(data.itemUsed, data.itemTotal)
    row(y, "Item cells", string.format("%d%%", math.floor(p * 100 + 0.5)),
        LIGHTGRAY, loadColour(p))
    bar(y + 1, p, loadColour(p))
    row(y + 2, "Bytes", fmt(data.itemUsed) .. " / " .. fmt(data.itemTotal))
    y = y + 4
  end

  -- fluid cells, only if the network has any
  if data.fluidTotal > 0 and y + 2 <= H then
    local p = pct(data.fluidUsed, data.fluidTotal)
    row(y, "Fluid cells", string.format("%d%%", math.floor(p * 100 + 0.5)),
        LIGHTGRAY, loadColour(p))
    bar(y + 1, p, loadColour(p))
    row(y + 2, "mB", fmt(data.fluidUsed) .. " / " .. fmt(data.fluidTotal))
    y = y + 4
  end

  -- footer
  if y <= H then rule(y); y = y + 1 end
  if y <= H then
    row(y, "Crafting CPUs",
        string.format("%d / %d", data.cpuBusy, data.cpuTotal),
        LIGHTGRAY, data.cpuBusy > 0 and YELLOW or WHITE)
    y = y + 1
  end
  if data.types and y <= H then
    row(y, "Item types", fmt(data.types))
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
print("Bridge:  " .. (bridge and "found" or "MISSING"))
print("Ctrl+T to stop.")

local function pollLoop()
  while true do
    poll()
    render()
    sleep(CONFIG.pollInterval)
  end
end

-- Re-fit when monitor blocks are added or removed.
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