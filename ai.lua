--[[
  ME CONTROLLER - PROCESSING DISPLAY
  Drives four Advanced Monitors (left, right, back, front) with
  random hex traffic and a header that reads as the controller
  working. Purely decorative -- it does not read the real network.

  Ctrl+T to stop.
]]

--==========================================================
-- CONFIG
--==========================================================

local CONFIG = {
  sides = { "left", "right", "back", "front" },
  scale = 0.5,
  delay = 0.1,    -- seconds per frame
  churn = 0.3,    -- fraction of rows redrawn per frame
}

-- CC colour slots are powers of two. Defined here so the script
-- never depends on the colors/colours tables.
local BLACK, ORANGE, WHITE = 32768, 2, 1
local GRAY, BROWN = 128, 4096

local CHARS = "0123456789ABCDEF"
local SPIN  = { "|", "/", "-", "\\" }

-- blit codes for the slots we repaint below.
-- 7 = gray slot, c = brown slot, 1 = orange slot, 0 = white slot.
local SHADES = {
  "7","7","7","7","7","7","7",  -- dim traffic
  "c","c","c",                  -- warm traffic
  "1","1",                      -- bright orange
  "0",                          -- white flash
}
local NSHADES = #SHADES

--==========================================================
-- FIND MONITORS
--==========================================================

local screens = {}

for _, side in ipairs(CONFIG.sides) do
  local m = peripheral.wrap(side)
  if m and m.setTextScale then
    m.setTextScale(CONFIG.scale)
    m.setPaletteColour(GRAY,   0x3a2a12)   -- dim amber
    m.setPaletteColour(BROWN,  0x8a5a14)   -- mid amber
    m.setPaletteColour(ORANGE, 0xf0a32a)   -- AE2 orange
    m.setBackgroundColour(BLACK)
    m.clear()
    local w, h = m.getSize()
    screens[#screens + 1] = { mon = m, side = side, w = w, h = h }
  end
end

if #screens == 0 then
  error("No monitors found on: " .. table.concat(CONFIG.sides, ", "), 0)
end

--==========================================================
-- DRAWING
--==========================================================

local function randomRow(w)
  local t, f = {}, {}
  for i = 1, w do
    local c = math.random(1, 16)
    t[i] = CHARS:sub(c, c)
    -- gaps keep it from looking like a solid block of digits
    if math.random() < 0.18 then t[i] = " " end
    f[i] = SHADES[math.random(1, NSHADES)]
  end
  return table.concat(t), table.concat(f)
end

local function drawHeader(s, frame)
  local spin = SPIN[(frame % #SPIN) + 1]
  local text = " ME CONTROLLER  " .. spin .. " PROCESSING"
  if #text > s.w then text = text:sub(1, s.w) end
  text = text .. string.rep(" ", s.w - #text)

  s.mon.setCursorPos(1, 1)
  s.mon.blit(text, string.rep("0", s.w), string.rep("1", s.w))

  if s.h >= 2 then
    s.mon.setCursorPos(1, 2)
    s.mon.blit(string.rep(" ", s.w), string.rep("0", s.w), string.rep("f", s.w))
  end
end

--==========================================================
-- RUN
--==========================================================

for _, s in ipairs(screens) do
  s.bg = string.rep("f", s.w)
  for y = 3, s.h do
    local t, f = randomRow(s.w)
    s.mon.setCursorPos(1, y)
    s.mon.blit(t, f, s.bg)
  end
end

print("Driving " .. #screens .. " monitor(s):")
for _, s in ipairs(screens) do print("  " .. s.side) end
print("Ctrl+T to stop.")

local frame = 0

local ok, err = pcall(function()
  while true do
    frame = frame + 1
    for _, s in ipairs(screens) do
      drawHeader(s, frame)
      local rows = math.max(1, math.floor((s.h - 2) * CONFIG.churn))
      for _ = 1, rows do
        local y = math.random(3, math.max(3, s.h))
        local t, f = randomRow(s.w)
        s.mon.setCursorPos(1, y)
        s.mon.blit(t, f, s.bg)
      end
    end
    sleep(CONFIG.delay)
  end
end)

--==========================================================
-- RESTORE
--==========================================================

for _, s in ipairs(screens) do
  s.mon.setPaletteColour(GRAY,   0x4C4C4C)
  s.mon.setPaletteColour(BROWN,  0x7F664C)
  s.mon.setPaletteColour(ORANGE, 0xF2B233)
  s.mon.setBackgroundColour(BLACK)
  s.mon.setTextColour(WHITE)
  s.mon.clear()
  s.mon.setCursorPos(1, 1)
end

if not ok then printError(err) end