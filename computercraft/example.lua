-- ex: ft=lua

-- This is a script I use to monitor my MFR BioReactors.
--
-- Top view:
--
-- ---------
-- IRON TANK (Railcraft)
-- ---VVV---
--    BCB
--
-- Front view:
--  BCB
--  SRS
--
-- The computer (C) sits beween two MFR BioReactors (B).
-- Each BioReactor is supplied by a Logistics Supplier Pipe (S).
-- Under the computer is a Logistics Request Pipe (R).
-- Three valves connect the BioReactors and computer to
-- an iron tank for the resulting biofuel.
--
-- The program does several things:
--
--   1. Monitors quantities of available ingredients.
--
--      There may be several items that all count as
--      a single ingredient; for example, 1 melon =
--      1 melon seed, or 1 pumpkin = 4 pumpkin seeds.
--
--   2. Shuts down the BioReactors if any ingredient
--      drops below the given threshold.
--
--      This is to prevent the BioReactors from running
--      on too few items, ruining efficiency and eating
--      all your items.
--
--   3. Sends ingredient quantities to DataDog.
--   4. Sends tank quantity + capacity to DataDog.
--   5. Calculates 5min, 30min, 60min BioReactor uptime
--      and sends to DataDog.
--
-- Just save this script as "startup" on a computer
-- in the same configuration, and you too can have a
-- ridiculous (or possibly ridiculously awesome)
-- BioReactor setup.

os.loadAPI("apis/statsd")

local pipe = peripheral.wrap("bottom")
local tank = peripheral.wrap("back")

loop_delay = 10
uptime_periods = {5, 30, 60} -- minutes
uptime = {}

uptime_trim = 3
for _, minutes in pairs(uptime_periods) do
  local cycles = minutes * 60 / loop_delay
  if cycles > uptime_trim then
    uptime_trim = cycles
  end
end

wanted_minimum = 256
wanted_fuels = {
  wheat_seeds  = {id295   = 1},
  barley_seeds = {id12659 = 1},
  potatoes     = {id392   = 1},
  carrots      = {id391   = 1},
  cactus_green = {id351_2 = 1},

  red_mushrooms   = {id40 = 1},
  brown_mushrooms = {id39 = 1},

  melon_seeds = {
    id360 = 1, -- melons
    id362 = 1  -- melon seeds
  },

  pumpkin_seeds = {
    id86  = 4, -- pumpkins (become 4x seeds)
    id361 = 1  -- seeds
  }
}

custom_stat_names = {
  id40 = "Red Mushroom",
  id39 = "Brown Mushroom"
}

needed = 0
wanted_by_idtag = {}
for fuel_name, id_table in pairs(wanted_fuels) do
  needed = needed + 1

  for idtag, multiplier in pairs(id_table) do
    wanted_by_idtag[idtag] = {fuel_name, multiplier}
  end
end

while true do
  term.clear()

  local fuels = {}
  for fuel_name, id_table in pairs(wanted_fuels) do
    fuels[fuel_name] = {items = {}, total = 0}
  end

  for key, item in pairs(pipe.getAvailableItems()) do
    local id = pipe.getItemID(item[1])
    local damage = pipe.getItemDamage(item[1])

    local idtag = "id" .. id
    if damage > 0 then
      idtag = idtag .. "_" .. damage
    end

    local wanted = wanted_by_idtag[idtag]

    if wanted then
      local name = pipe.getUnlocalizedName(item[1])
      local quantity = item[2]

      local stat_name = custom_stat_names[idtag] or name
      statsd.gauge("bioreactor.fuels.raw", quantity, {tags = {item = stat_name}})

      local fuel_name  = wanted[1]
      local multiplier = wanted[2]

      fuels[fuel_name]['items'][name] = quantity
      fuels[fuel_name]['total'] =
        fuels[fuel_name]['total'] + (quantity * multiplier)
    end
  end

  local missing = 0
  for fuel_name, data in pairs(fuels) do
    output = ""
    for name, quantity in pairs(data['items']) do
      if string.len(output) > 0 then
        output = output .. " + "
      end
      output = output .. quantity .. " " .. name
    end

    total  = data['total']
    output = output .. " = " .. total
    
    if total >= wanted_minimum then
      output = output .. " (okay)"
    else
      output = output .. " (too low!)"
      missing = missing + 1
    end

    statsd.gauge("bioreactor.fuels", total, {tags = {item = fuel_name}})
    print(output)
  end

  statsd.gauge("bioreactor.missing", missing)

  local enabled = false
  if missing == 0 then
    print("All quantities okay.  BioReactors enabled!")
    enabled = true
  else
    print("Missing " .. missing .. " items.  BioReactors disabled. :(")
  end

  redstone.setOutput("left",  not enabled)
  redstone.setOutput("right", not enabled)

  table.insert(uptime, enabled)
  local uptime_count = table.maxn(uptime)

  if uptime_count > uptime_trim * 5 then
    -- Garbage collection at 5x the limit (i.e. sparingly):
    local new_uptime = {}
    for i = uptime_count - uptime_trim + 1, uptime_count do
      table.insert(new_uptime, uptime[i])
    end
    uptime = new_uptime
    uptime_count = uptime_trim
  end

  print()

  for key, minutes in pairs(uptime_periods) do
    local cycles = minutes * 60 / loop_delay
    local enabled = 0

    if cycles > uptime_count then
      cycles = uptime_count
    end

    for i = uptime_count - cycles + 1, uptime_count do
      if uptime[i] then
        enabled = enabled + 1
      end
    end

    local percent = 100.0 * enabled / cycles
    print(string.format(
      minutes .. " minute uptime: %d of %d cycles (%.2f%%)",
      enabled, cycles, percent
    ))
    statsd.gauge("bioreactor.uptime." .. minutes .. "min", percent)
  end

  local tank_info = tank.getTankInfo("unknown")[1]
  statsd.gauge("bioreactor.tank.amount",   tank_info.amount)
  statsd.gauge("bioreactor.tank.capacity", tank_info.capacity)

  sleep(loop_delay)
end
