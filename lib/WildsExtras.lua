-- Port of local Wilds of Kanto 0.4.5 town-spawn + reachable-tile extras
-- onto public overworld_wild_spawns (0.4.2) from FOLLOWERS_EX.
return function(hostMod)
  local WILDS_ID = "overworld_wild_spawns"

  local DEFAULT_TOWN_GRASS = {
    rate = 25,
    slots = {
      { species = "RATTATA", level = 3 },
      { species = "RATTATA", level = 3 },
      { species = "PIDGEY", level = 3 },
      { species = "PIDGEY", level = 4 },
      { species = "RATTATA", level = 4 },
      { species = "PIDGEY", level = 4 },
      { species = "RATTATA", level = 5 },
      { species = "PIDGEY", level = 5 },
      { species = "RATTATA", level = 5 },
      { species = "PIDGEY", level = 5 },
    },
  }

  local function optBool(key, default)
    local ok, got = pcall(hostMod.options.get, hostMod.options, key)
    if not ok or got == nil then return default end
    return got and true or false
  end

  local function filterPlayerReachable(map, player, cells, game, mode)
    if not map or not player or type(cells) ~= "table" or #cells == 0 then
      return cells or {}
    end
    local px, py = player.cellX, player.cellY
    if px == nil or py == nil then return cells end

    local w = map.widthCells or 0
    local h = map.heightCells or 0
    local function inBounds(x, y)
      if x < 0 or y < 0 or x >= w or y >= h then return false end
      if map.inBounds and not map:inBounds(x, y) then return false end
      return true
    end

    local function isPassable(x, y)
      if not inBounds(x, y) then return false end
      if mode == "water" then
        return map.isWaterCell and map:isWaterCell(x, y)
      end
      if map.isWalkableCell and not map:isWalkableCell(x, y) then return false end
      if map.isWaterCell and map:isWaterCell(x, y) then return false end
      return true
    end

    local dirs = {
      { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 },
    }
    local ledges = game and game.data and game.data.field and game.data.field.ledges
    local tileset = map.def and map.def.tileset

    local function ledgeLanding(x, y, dirName, dx, dy)
      if type(ledges) ~= "table" or not map.cellTile then return nil end
      local fx, fy = x + dx, y + dy
      if not inBounds(fx, fy) then return nil end
      local standing = map:cellTile(x, y)
      local front = map:cellTile(fx, fy)
      for _, ledge in ipairs(ledges) do
        if (ledge.tileset or "OVERWORLD") == tileset
           and ledge.facing == dirName and ledge.input == dirName
           and ledge.standingTile == standing and ledge.ledgeTile == front then
          local lx, ly = fx + dx, fy + dy
          if inBounds(lx, ly) and isPassable(lx, ly) then
            return lx, ly
          end
        end
      end
      return nil
    end

    local seen = {}
    local queue = {}
    local function enqueue(x, y)
      local key = x .. "," .. y
      if seen[key] then return end
      if not isPassable(x, y) and not (x == px and y == py) then return end
      seen[key] = true
      queue[#queue + 1] = { x, y }
    end

    enqueue(px, py)
    if #queue == 0 then
      seen[px .. "," .. py] = true
      queue[1] = { px, py }
    end

    local qi = 1
    while qi <= #queue do
      local x, y = queue[qi][1], queue[qi][2]
      qi = qi + 1
      for _, d in ipairs(dirs) do
        local dirName, dx, dy = d[1], d[2], d[3]
        local nx, ny = x + dx, y + dy
        if isPassable(nx, ny) then
          enqueue(nx, ny)
        else
          local lx, ly = ledgeLanding(x, y, dirName, dx, dy)
          if lx then enqueue(lx, ly) end
        end
      end
    end

    local out = {}
    for _, cell in ipairs(cells) do
      if seen[cell.x .. "," .. cell.y] then
        out[#out + 1] = cell
      end
    end
    return out
  end

  local function wildsIsModern(wilds)
    -- 0.5.7+ / 0.6.0: native follow-sprites + EnhancedWorldSprite. Our
    -- initializeForMap / Surface.resolve inject breaks their spawn pipeline.
    local render = wilds and wilds.exports and wilds.exports.render
    if render and (type(render.attachEnhancedToEntity) == "function"
                   or type(render.syncEntityAnimation) == "function") then
      return true
    end
    local ver = tostring((wilds and wilds.version) or "")
    local maj, min = ver:match("^(%d+)%.(%d+)")
    maj, min = tonumber(maj), tonumber(min)
    if maj and min and (maj > 0 or min >= 5) then
      return true
    end
    return false
  end

  local function install(wilds)
    if not wilds or not wilds.exports or not wilds.exports.logic then return false end
    local logic = wilds.exports.logic
    if logic._followersExWildsExtras then return true end
    -- Local Wilds 0.4.5+ already has town/reachable — don't double-wrap.
    if type(logic._tryTownSurface) == "function" then
      hostMod.log:info("WildsExtras: native town support present; skip")
      return true
    end
    -- Wilds 0.5.7+/0.6: still inject town borrow + reachable filter. The
    -- Surface.resolve patch is scoped to initializeForMap only.
    if wildsIsModern(wilds) then
      hostMod.log:info("WildsExtras: Wilds %s — installing town/reachable (modern)",
        tostring(wilds.version or "?"))
    end

    local V = wilds.exports.lib
    local Surface, Grass, EncounterPick, EncounterIndex
    if type(V) == "table" and type(V.require) == "function" then
      local ok1, s = pcall(V.require, "surface")
      local ok2, g = pcall(V.require, "grass")
      local ok3, ep = pcall(V.require, "encounter_pick")
      local ok4, ei = pcall(V.require, "encounter_index")
      if ok1 then Surface = s end
      if ok2 then Grass = g end
      if ok3 then EncounterPick = ep end
      if ok4 then EncounterIndex = ei end
    end

    if not (Surface and Grass and EncounterPick and EncounterIndex) then
      hostMod.log:warn("WildsExtras: could not resolve Wilds libs; town/reachable skipped")
      return false
    end

    if not Surface.TOWN then
      Surface.TOWN = "TOWN"
      Surface.BEHAVIORS = Surface.BEHAVIORS or {}
      Surface.BEHAVIORS[Surface.TOWN] = {
        "IDLE_LOOK", "GRASS_WANDER", "AGGRESSIVE",
      }
    end

    if type(Grass.filterPlayerReachable) ~= "function" then
      Grass.filterPlayerReachable = filterPlayerReachable
    end

    if type(logic._borrowTownEncDef) ~= "function" then
      function logic:_borrowTownEncDef(mapId, game, map)
        local encounters = game and game.data and game.data.encounters
        if type(encounters) ~= "table" then
          return { grass = DEFAULT_TOWN_GRASS }, "default:town"
        end
        local native = encounters[mapId]
        if EncounterPick.hasGrassTable(native) then
          return native, "native"
        end
        local seen = { [tostring(mapId)] = true }
        local dirs = { "north", "south", "east", "west" }
        if map and map.def and type(map.def.connections) == "table" then
          for _, dir in ipairs(dirs) do
            local conn = map.def.connections[dir]
            local dest = conn and (conn.map or conn.mapId or conn.dest)
            if dest and not seen[tostring(dest)] then
              seen[tostring(dest)] = true
              local enc = encounters[dest]
              if EncounterPick.hasGrassTable(enc) then
                return { grass = enc.grass }, "borrow:" .. tostring(dest)
              end
            end
          end
        end
        return { grass = DEFAULT_TOWN_GRASS }, "default:town"
      end
    end

    if type(logic._tryTownSurface) ~= "function" then
      function logic:_tryTownSurface(mapId, game, map, encDef, surfaceInfo)
        if surfaceInfo and surfaceInfo.supported then
          return encDef, surfaceInfo, nil
        end
        if not optBool("wilds_town_spawns", false) then
          return encDef, surfaceInfo, nil
        end
        local mapType = EncounterIndex.mapTypeOf(game, mapId)
        if mapType ~= "town" then
          return encDef, surfaceInfo, nil
        end
        if Surface.isIndoorEncounterMap and Surface.isIndoorEncounterMap(game, map) then
          return encDef, surfaceInfo, nil
        end
        local borrowed, source = self:_borrowTownEncDef(mapId, game, map)
        if not borrowed or not EncounterPick.hasGrassTable(borrowed) then
          return encDef, surfaceInfo, nil
        end
        self._encOverride = borrowed
        self._encOverrideMapId = mapId
        local info = {
          surface = Surface.TOWN,
          encounterKind = "grass",
          tileMode = "walkable",
          supported = true,
          grassTileCount = 0,
          reason = nil,
          townSource = source,
        }
        return borrowed, info, source
      end
    end

    local bareEncDef = logic._encDef

    -- 0.4.5: honor town enc override in _encDef.
    if not logic._followersExEncDefWrapped and type(bareEncDef) == "function" then
      function logic:_encDef(mapId, game)
        if self._encOverride and self._encOverrideMapId == mapId then
          return self._encOverride
        end
        return bareEncDef(self, mapId, game)
      end
      logic._followersExEncDefWrapped = true
    end

    -- Inject town surface + reachable filter into public initializeForMap.
    if not logic._followersExInitWrapped and type(logic.initializeForMap) == "function" then
      local origInit = logic.initializeForMap
      function logic:initializeForMap(mapId, game)
        self._encOverride = nil
        self._encOverrideMapId = nil

        local Game = require("src.core.Game")
        game = game or Game
        local world = self.mod and self.mod.world
        local ow = world and world.overworld and world:overworld()
        local townSource

        -- Pre-seed town enc override so _encDef / Surface.resolve see a table.
        if ow and ow.map and ow.map.id == mapId and optBool("wilds_town_spawns", false)
           and type(bareEncDef) == "function" then
          local bare = bareEncDef(self, mapId, game)
          local bareInfo = Surface.resolve(game, ow.map, bare)
          local _, info2, src = self:_tryTownSurface(
            mapId, game, ow.map, bare, bareInfo or { supported = false })
          if info2 and info2.supported then
            townSource = src
          end
        end

        local origResolve = Surface.resolve
        function Surface.resolve(g, map, encDef)
          local info = origResolve(g, map, encDef)
          if info and info.supported then return info end
          if self._encOverride and self._encOverrideMapId == mapId then
            return {
              surface = Surface.TOWN,
              encounterKind = "grass",
              tileMode = "walkable",
              supported = true,
              grassTileCount = 0,
              reason = nil,
              townSource = townSource,
            }
          end
          return info
        end

        local ok, result = pcall(origInit, self, mapId, game)
        Surface.resolve = origResolve
        if not ok then error(result) end

        if result and townSource and self.state then
          self.state.encounterSource = "town:" .. tostring(townSource)
        end

        -- Always filter to player-reachable tiles (ledges count as passable).
        if result and self.eligibleCache and #self.eligibleCache > 0 then
          if ow and ow.map and ow.player and self.surfaceInfo then
            local before = #self.eligibleCache
            self.eligibleCache = Grass.filterPlayerReachable(
              ow.map, ow.player, self.eligibleCache, game,
              self.surfaceInfo.tileMode)
            if self.state then
              self.state.eligibleTileCount = #self.eligibleCache
            end
            if #self.eligibleCache < before and self._log then
              self:_log("FOLLOWERS_EX reachable filter: %d -> %d",
                        before, #self.eligibleCache)
            end
          end
        end
        return result
      end
      logic._followersExInitWrapped = true
    end

    logic._followersExWildsExtras = true
    hostMod.log:info("WildsExtras installed (town spawns + reachable tiles)")
    return true
  end

  return {
    install = install,
    wildsId = WILDS_ID,
  }
end
