--[[
  HEX GRID
  Fills an Advanced Monitor with random hex values.
  Each value is a whole token coloured a single shade -- gray, green
  or dark red -- so the screen reads as a data dump rather than noise.

  Only a fraction of rows are rerolled each frame (see CONFIG.churn),
  which makes it look like values updating instead of static.

  Ctrl+T to stop.
]]

local CONFIG = {
  side   = "right",   -- or nil to auto-detect
  scale  = 0.5,       -- smallest CC allows
  delay  = 0.15,      -- seconds per frame
  churn  = 0.25,      -- fraction of rows redrawn per frame (0-1)
  minLen = 2,         -- shortest hex value, in digits
  maxLen = 4,         -- longest
  maxGap = 3,         -- spaces between values
  prefix = "",        -- set to "0x" to prefix each value
}

local HEX = "0123456789ABCDEF"

local mon = CONFIG.side and peripheral.wrap(CONFIG.side) or peripheral.find("monitor")
if not mon then error("No monitor found", 0) end
if not mon.isColour or not mon.isColour() then
  error("Needs an advanced (gold) monitor", 0)
end

mon.setTextScale(CONFIG.scale)

mon.setPaletteColour(colours.gray,  0x555555)  -- gray
mon.setPaletteColour(colours.green, 0x3fbf46)  -- green
mon.setPaletteColour(colours.brown, 0x7a1a12)  -- dark red

-- Weighted: repeat a code to make that shade commoner.
local SHADES = {
  "7","7","7","7","7","7",  -- gray
  "d","d","d",              -- green
  "c","c",                  -- dark red
}
local NSHADES = #SHADES

mon.setBackgroundColour(colours.black)
mon.clear()

local w, h = mon.getSize()

local function buildRow()
  local t, f = {}, {}
  local i = 1
  while i <= w do
    local shade = SHADES[math.random(1, NSHADES)]

    local token = CONFIG.prefix
    for _ = 1, math.random(CONFIG.minLen, CONFIG.maxLen) do
      local c = math.random(1, 16)
      token = token .. HEX:sub(c, c)
    end

    for k = 1, #token do
      if i > w then break end
      t[i], f[i] = token:sub(k, k), shade
      i = i + 1
    end

    for _ = 1, math.random(1, CONFIG.maxGap) do
      if i > w then break end
      t[i], f[i] = " ", shade
      i = i + 1
    end
  end
  return table.concat(t), table.concat(f)
end

-- Cache every row so partial redraws keep the rest of the screen intact.
local rows = {}
for y = 1, h do
  local t, f = buildRow()
  rows[y] = { t = t, f = f }
end

local BG = string.rep("f", w)

local function drawRow(y)
  mon.setCursorPos(1, y)
  mon.blit(rows[y].t, rows[y].f, BG)
end

for y = 1, h do drawRow(y) end

local perFrame = math.max(1, math.floor(h * CONFIG.churn))

local ok, err = pcall(function()
  while true do
    for _ = 1, perFrame do
      local y = math.random(1, h)
      local t, f = buildRow()
      rows[y] = { t = t, f = f }
      drawRow(y)
    end
    sleep(CONFIG.delay)
  end
end)

for _, c in pairs({colours.gray, colours.green, colours.brown}) do
  mon.setPaletteColour(c, term.nativePaletteColour(c))
end
mon.setBackgroundColour(colours.black)
mon.setTextColour(colours.white)
mon.clear()
mon.setCursorPos(1, 1)

if not ok then printError(err) end