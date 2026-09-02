local mon = peripheral.wrap("right")
mon.setTextScale(0.5)
mon.setBackgroundColour(colours.black)
mon.clear()

local w, h = mon.getSize()
local chars = "0123456789"
local shades = { "5", "d", "7" }   -- lime, green, gray

while true do
    for y = 1, h do
        local t, f, b = {}, {}, {}
        for i = 1, w do
            local x = math.random(1, #chars)
            t[i] = chars:sub(x, x)
            f[i] = shades[math.random(1, 3)]
            b[i] = "f"
        end
        mon.setCursorPos(1, y)
        mon.blit(table.concat(t), table.concat(f), table.concat(b))
    end
    sleep(0.08)
end