-- Control / pack / trailer engine (ported from local PokePCFollowers 1.5.0).
-- hostMod = FOLLOWERS_EX; assetMod = PokePCFollowers_VoxelMerge (sprites).
-- NOTE: mod:find() returns {id, version, exports} — it does NOT include .path.
return function(hostMod, assetMod)
  local mod = hostMod
  local POKE_ID = (assetMod and assetMod.id) or "PokePCFollowers_VoxelMerge"

  local function fsExists(path)
    if type(path) ~= "string" or path == "" then return false end
    local fs = love and love.filesystem
    if not (fs and fs.getInfo) then return false end
    local ok, info = pcall(fs.getInfo, path)
    return ok and info ~= nil
  end

  local function resolveAssetRoot()
    -- Full mod API (rare) may carry .path; find-handle does not.
    if assetMod and type(assetMod.path) == "string" and assetMod.path ~= "" then
      local probe = assetMod.path .. "/assets/sprites/follower_CHARMANDER.png"
      if fsExists(probe) then return assetMod.path end
    end
    local hostPath = tostring(hostMod.path or "")
    local candidates = {
      -- Sibling of FOLLOWERS_EX under the same mods/ root.
      hostPath:gsub("[^/\\]+$", POKE_ID),
      "mods/" .. POKE_ID,
    }
    for _, root in ipairs(candidates) do
      if root and root ~= "" and root ~= hostPath
         and fsExists(root .. "/assets/sprites/follower_CHARMANDER.png") then
        return root
      end
    end
    return nil
  end

  local assetRoot = resolveAssetRoot()
  if not assetRoot then
    error("ControlEngine: cannot find PokePC follower sprites (id="
      .. tostring(POKE_ID) .. ")", 0)
  end
  print("[FOLLOWERS_EX] ControlEngine installing (assetRoot=" .. tostring(assetRoot) .. ")")

  local Game = require("src.core.Game")
  local PaletteFX = require("src.render.PaletteFX")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Assets = require("src.render.Assets")
  local BattleState = require("src.battle.BattleState")
  local PikachuFollower = require("src.world.PikachuFollower")
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local FieldDefaults = require("src.world.FieldDefaults")
  local Sprites = require("src.pokemon.Sprites")
  local Boxes = require("src.pokemon.Boxes")
  local Stats = require("src.pokemon.Stats")
  local NPC = require("src.world.NPC")

  -- control_mode / follower_count UI live in FOLLOWERS_EX (separate credit).
  -- Runtime still reads save.pokepcControlMode / pokepcFollowerCount.
  local optCache = {}
  local function opt(key, default)
    if optCache[key] ~= nil then return optCache[key] end
    local ok, got = pcall(mod.options.get, mod.options, key)
    if ok and got ~= nil and type(got) ~= "boolean" then
      optCache[key] = got
      return got
    end
    optCache[key] = default
    return default
  end

  mod.events:on("mod.options_changed", function(payload)
    if payload and (payload.mod == mod.id) then
      optCache = {}
    end
  end)

  local function controlMode(game)
    game = game or Game
    local saved = game and game.save and game.save.pokepcControlMode
    if saved == "lead" then saved = "lead_trainer" end -- migrate old id
    if type(saved) == "string" and saved ~= "" then return saved end
    return tostring(opt("control_mode", "follow"))
  end

  local function followerCount(game)
    game = game or Game
    local saved = game and game.save and game.save.pokepcFollowerCount
    if type(saved) == "number" then return math.max(0, math.min(6, saved)) end
    return tonumber(opt("follower_count", 1)) or 1
  end

  local function setFollowerCount(game, n)
    n = math.max(0, math.min(6, math.floor(tonumber(n) or 0)))
    optCache.follower_count = n
    if game and game.save then game.save.pokepcFollowerCount = n end
    -- Options persistence owned by FOLLOWERS_EX UI (persistOpt).
  end

  local function setControlMode(game, mode)
    mode = mode or "follow"
    optCache.control_mode = mode
    if game and game.save then game.save.pokepcControlMode = mode end
    -- Options persistence owned by FOLLOWERS_EX UI (persistOpt).
  end

  local function isPokemonFront(game)
    local m = controlMode(game)
    return m == "pokemon" or m == "lead_trainer" or m == "pack"
  end

  -- ------- Leader (party or box)
  local function clearLeader(game)
    if game and game.save then
      game.save.pokepcLeader = nil
      game.save.followerPartyIndex = nil
    end
  end

  local function bustLeaderVisual(game)
    local player = game and game.overworld and game.overworld.player
    if player then
      -- Force applyPlayerAsPokemon to rebuild after leader changes.
      player._pokepcControlSpecies = nil
    end
  end

  local function setLeaderParty(game, partyIndex)
    if not game or not game.save then return end
    game.save.pokepcLeader = { source = "party", index = partyIndex }
    game.save.followerPartyIndex = partyIndex
    bustLeaderVisual(game)
  end

  local function setLeaderBox(game, boxNum, slotIndex)
    if not game or not game.save then return end
    game.save.pokepcLeader = {
      source = "box", box = boxNum, index = slotIndex,
    }
    bustLeaderVisual(game)
  end

  local function getLeaderMon(game)
    if not game or not game.save then return nil end
    local save = game.save
    local lead = save.pokepcLeader
    if lead and lead.source == "box" then
      Boxes.ensure(save)
      local boxes = save.boxes or {}
      local box = boxes[lead.box or save.currentBox or 1]
      local mon = box and box[lead.index]
      if mon then return mon, "box" end
    end
    if lead and lead.source == "party" then
      local mon = save.party and save.party[lead.index]
      if mon and (mon.hp or 0) >= 0 then return mon, "party" end
    end
    -- Legacy / fallback: followerPartyIndex or first healthy party mon
    local idx = save.followerPartyIndex
    if idx and save.party and save.party[idx] then
      return save.party[idx], "party"
    end
    for _, mon in ipairs(save.party or {}) do
      if (mon.hp or 0) > 0 then return mon, "party" end
    end
    return save.party and save.party[1], "party"
  end

  local function getActiveFollowerMon(game)
    return (getLeaderMon(game))
  end

  local function monIdentityKey(mon)
    if not mon then return nil end
    local dvs = mon.dvs
    local dvKey = ""
    if type(dvs) == "table" then
      dvKey = table.concat({
        tostring(dvs.attack), tostring(dvs.defense),
        tostring(dvs.speed), tostring(dvs.special),
      }, ",")
    elseif dvs ~= nil then
      dvKey = tostring(dvs)
    end
    return table.concat({
      tostring(mon.species or ""),
      tostring(mon.level or ""),
      tostring(mon.nickname or ""),
      tostring(mon.otId or ""),
      dvKey,
    }, "|")
  end

  local function leaderPartyIndex(game, leader, leadSrc)
    local save = game and game.save
    if not save then return nil end
    local lead = save.pokepcLeader
    if lead and lead.source == "party" and type(lead.index) == "number" then
      return lead.index
    end
    if leadSrc == "party" and leader then
      for i, mon in ipairs(save.party or {}) do
        if mon == leader then return i end
      end
    end
    if type(save.followerPartyIndex) == "number" then
      return save.followerPartyIndex
    end
    return nil
  end

  local function partyTrailMons(game)
    -- Party mons that may trail (healthy). When the player IS the pokemon,
    -- never trail the controlled leader (by index / identity) — otherwise a
    -- mon can "follow itself". Trainer-walk puts the leader first.
    local save = game and game.save
    if not save then return {} end
    local leader, leadSrc = getLeaderMon(game)
    local leadIdx = leaderPartyIndex(game, leader, leadSrc)
    local leadKey = monIdentityKey(leader)
    local front = isPokemonFront(game)
    local out = {}
    local function push(mon, i)
      out[#out + 1] = { mon = mon, partyIndex = i }
    end
    local function isControlledLeader(mon, i)
      if not mon then return false end
      if leadIdx and i == leadIdx then return true end
      if leader and mon == leader then return true end
      if leadKey and monIdentityKey(mon) == leadKey then return true end
      return false
    end

    if not front and leader then
      if leadIdx and save.party and save.party[leadIdx]
         and (save.party[leadIdx].hp or 0) > 0 then
        push(save.party[leadIdx], leadIdx)
      else
        for i, mon in ipairs(save.party or {}) do
          if isControlledLeader(mon, i) and (mon.hp or 0) > 0 then
            push(mon, i)
            break
          end
        end
      end
    end
    for i, mon in ipairs(save.party or {}) do
      if (mon.hp or 0) > 0 and not isControlledLeader(mon, i) then
        push(mon, i)
      end
    end
    local n = followerCount(game)
    while #out > n do out[#out] = nil end
    return out
  end

  -- ------- Sprites (must run during mod load; content freezes before mods.loaded)
  pcall(function()
    mod.content.sprites:patch("SPRITE_PIKACHU", {
      image = assetRoot .. "/assets/sprites/follower_CHARMANDER.png",
      frames = 6,
      walker = true,
      trueColor = true,
    })
  end)

  local followerImgCache = {}
  local function followerPath(species)
    return assetRoot .. "/assets/sprites/follower_"
      .. tostring(species or "CHARMANDER") .. ".png"
  end

  -- Cache key includes shiny so one shiny mon cannot tint every trailer.
  local function getFollowerImage(species, shiny)
    species = species or "CHARMANDER"
    local key = tostring(species) .. (shiny and "#S" or "#N")
    if followerImgCache[key] then return followerImgCache[key] end
    local path = followerPath(species)
    local img
    if shiny then
      local shinyMod = mod:find("SHINY_POKEMON")
      local bake = shinyMod and shinyMod.exports and shinyMod.exports.bakeFollowerOwSheet
      if type(bake) == "function" then
        local ok, baked = pcall(bake, path, species)
        if ok and baked then img = baked end
      end
    end
    if not img then
      local ok, loaded = pcall(Assets.image, path)
      img = ok and loaded or nil
    end
    if not img then
      img = Assets.image(followerPath("CHARMANDER"))
    end
    followerImgCache[key] = img
    return img
  end

  local trainerWalkPath, trainerWalkImg
  local function trainerWalkDef(game)
    local data = game and game.data
    if not data then return nil end
    local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
    return walkId and data.sprites and data.sprites[walkId]
  end

  local function getTrainerWalkImage(game)
    local def = trainerWalkDef(game)
    local path = def and def.image
    if type(path) ~= "string" then return nil end
    if trainerWalkPath == path and trainerWalkImg then return trainerWalkImg end
    local ok, img = pcall(Assets.image, path)
    if ok and img then
      trainerWalkPath, trainerWalkImg = path, img
      return img
    end
    return nil
  end

  -- ------- Player as pokemon
  local function restorePlayerTrainerSprite(game, ow)
    local player = ow and ow.player
    if not player or not game or not game.data then return end
    if not player._pokepcAsPokemon then return end
    local def = trainerWalkDef(game)
    if not def then return end
    player.sprite = SpriteRenderer.new(def, "player")
    player._pokepcAsPokemon = nil
    player._pokepcControlSpecies = nil
  end

  local function applyPlayerAsPokemon(game, ow)
    local player = ow and ow.player
    if not player then return end
    if player.surfing or player.onBike or player.fishing then
      restorePlayerTrainerSprite(game, ow)
      return
    end
    local mon = getLeaderMon(game)
    local species = mon and mon.species or "CHARMANDER"
    local path = followerPath(species)
    local shiny = mon and Stats.isShiny and Stats.isShiny(mon.dvs)
    if player._pokepcAsPokemon and player._pokepcControlSpecies == species
       and player._pokepcShiny == (shiny and true or false)
       and player.sprite and player.sprite.def
       and player.sprite.def.image == path then
      return
    end
    local ok, sprite = pcall(SpriteRenderer.new, {
      id = "SPRITE_PLAYER_POKEMON",
      image = path, frames = 6, walker = true, trueColor = true,
      pokepcShiny = shiny and true or false,
    }, "player")
    if ok and sprite then
      player.sprite = sprite
      player._pokepcAsPokemon = true
      player._pokepcControlSpecies = species
      player._pokepcShiny = shiny and true or false
    end
  end

  local function syncPlayerControlVisual(game, ow)
    if isPokemonFront(game) then
      applyPlayerAsPokemon(game, ow)
    else
      restorePlayerTrainerSprite(game, ow)
    end
  end

  -- ------- Multi-trailer pack (replaces greying / double-leader bugs)
  local TRAILER_BASE = 240

  local function removeTrailers(ow)
    if not ow then return end
    local keepNpcs, keepEnt = {}, {}
    for _, npc in ipairs(ow.npcs or {}) do
      if not npc.pokepcTrailer then keepNpcs[#keepNpcs + 1] = npc end
    end
    for _, e in ipairs(ow.entities or {}) do
      if not e.pokepcTrailer then keepEnt[#keepEnt + 1] = e end
    end
    ow.npcs, ow.entities = keepNpcs, keepEnt
    ow.pokepcTrailers = {}
    ow.pokepcTrailCells = {}
  end

  local function makeTrailer(game, ow, x, y, facing, kind, mon, slot)
    local npc = NPC.new(game.data, ow.map.id, {
      index = TRAILER_BASE + slot,
      name = "POKEPC_TRAILER_" .. tostring(slot),
      sprite = "SPRITE_PIKACHU",
      movement = "STAY", range = "NONE", x = x, y = y,
    })
    npc.pokepcTrailer = true
    npc.pokepcTrailerKind = kind
    npc.pokepcTrailerId = kind .. ":" .. tostring(slot)
    npc.pokepcMon = mon
    npc.passable = true
    npc.facing = facing or "down"
    npc.pikachuFollower = false

    if kind == "trainer" then
      -- Walk sheets are DMG greyscale; color comes from OBP / map bake.
      -- trueColor would draw the raw greys (the "greyed out trainer" bug).
      local def = trainerWalkDef(game)
      if def then
        npc.sprite = SpriteRenderer.new({
          id = def.id or "SPRITE_RED",
          image = def.image,
          frames = def.frames or 6,
          walker = def.walker ~= false,
          source = def.source,
          paletteSource = def.paletteSource,
        }, npc.id)
      end
    else
      local species = mon and mon.species or "CHARMANDER"
      local shiny = mon and Stats.isShiny and Stats.isShiny(mon.dvs)
      npc.pokepcShiny = shiny and true or false
      npc.sprite = SpriteRenderer.new({
        id = "SPRITE_POKEPC_MON",
        image = followerPath(species),
        frames = 6, walker = true, trueColor = true,
        pokepcShiny = npc.pokepcShiny,
      }, npc.id)
    end

    npc.walkPhase = function(self)
      if self.moving then
        return NPC.walkPhase(self)
      end
      return 0
    end
    return npc
  end

  -- cells[i] = goal tile for trailer i (1 = first behind the player).
  local function behindOffset(facing, steps)
    local dx = facing == "left" and 1 or facing == "right" and -1 or 0
    local dy = facing == "up" and 1 or facing == "down" and -1 or 0
    return dx * steps, dy * steps
  end

  local function syncTrailers(game, ow)
    if not ow or not ow.player or not ow.map then return end
    local mode = controlMode(game)
    local want = {}

    -- Solo "pokemon" with a pack size still trails party mons (no trainer NPC).
    -- TRAINER FOLLOWS off maps here; only explicit count 0 stays truly alone.
    if mode == "pokemon" and followerCount(game) > 0 then
      mode = "pack"
    end

    if mode == "lead_trainer" then
      -- Mons first (closest to the leader); trainer brings up the rear.
      for _, entry in ipairs(partyTrailMons(game)) do
        want[#want + 1] = { kind = "mon", mon = entry.mon }
      end
      want[#want + 1] = { kind = "trainer", mon = nil }
    elseif mode == "follow" or mode == "pack" then
      for _, entry in ipairs(partyTrailMons(game)) do
        want[#want + 1] = { kind = "mon", mon = entry.mon }
      end
    end
    -- mode == "pokemon" and count 0: solo leader, no trailers

    local trailers = ow.pokepcTrailers or {}
    local dirty = #trailers ~= #want
    if not dirty then
      for i, spec in ipairs(want) do
        local t = trailers[i]
        if not t or t.pokepcTrailerKind ~= spec.kind then dirty = true break end
        if spec.kind == "mon" then
          local sp = spec.mon and spec.mon.species
          local cur = t.pokepcMon and t.pokepcMon.species
          if sp ~= cur then dirty = true break end
        end
      end
    end

    local p = ow.player
    local facing = p.facing or "down"

    if dirty then
      removeTrailers(ow)
      trailers = {}
      local goals = {}
      local px, py = p.cellX, p.cellY
      for i, spec in ipairs(want) do
        local ox, oy = behindOffset(facing, i)
        local bx, by = px + ox, py + oy
        if not (ow.map:inBounds(bx, by) and ow.map:isWalkableCell(bx, by)) then
          -- Fall back toward the player until a walkable cell is found.
          bx, by = px, py
          for s = i, 1, -1 do
            local sx, sy = behindOffset(facing, s)
            local tx, ty = px + sx, py + sy
            if ow.map:inBounds(tx, ty) and ow.map:isWalkableCell(tx, ty) then
              bx, by = tx, ty
              break
            end
          end
        end
        local okNpc, npc = pcall(makeTrailer, game, ow, bx, by, facing,
                                      spec.kind, spec.mon, i)
        if not okNpc or not npc then
          print("[FOLLOWERS_EX] trailer spawn failed slot " .. tostring(i)
            .. ": " .. tostring(npc))
        else
          npc.px, npc.py = bx * 16, by * 16
          table.insert(ow.npcs, npc)
          table.insert(ow.entities, npc)
          local slot = #trailers + 1
          trailers[slot] = npc
          goals[slot] = { x = bx, y = by }
        end
      end
      ow.pokepcTrailers = trailers
      ow.pokepcTrailCells = goals
      ow.pokepcTrailHead = { x = px, y = py }
    end

    -- Queue a trail beat when the player COMMITS a step (same as
    -- PikachuFollower): head tracks the destination; each trailer shifts
    -- into the cell the one ahead vacated.
    local destX = p.targetX or p.cellX
    local destY = p.targetY or p.cellY
    ow.pokepcTrailHead = ow.pokepcTrailHead or { x = p.cellX, y = p.cellY }
    local head = ow.pokepcTrailHead
    if destX ~= head.x or destY ~= head.y then
      local goals = ow.pokepcTrailCells or {}
      for i = #trailers, 2, -1 do
        local prev = goals[i - 1]
        goals[i] = prev and { x = prev.x, y = prev.y } or { x = head.x, y = head.y }
      end
      if #trailers >= 1 then
        goals[1] = { x = head.x, y = head.y }
      end
      ow.pokepcTrailCells = goals
      head.x, head.y = destX, destY
    end

    local goals = ow.pokepcTrailCells or {}
    for i, npc in ipairs(trailers) do
      if npc.moving then
        -- NPC:update owns px/py mid-step; do not overwrite.
      else
        local cell = goals[i] or { x = p.cellX, y = p.cellY }
        local gx, gy = cell.x, cell.y
        if npc.cellX ~= gx or npc.cellY ~= gy then
          local far = math.abs((npc.cellX or 0) - gx) + math.abs((npc.cellY or 0) - gy)
          if far > 6 then
            npc.cellX, npc.cellY = gx, gy
            npc.px, npc.py = gx * 16, gy * 16
            npc.targetX, npc.targetY = nil, nil
          else
            local dir
            if npc.cellX < gx then dir = "right"
            elseif npc.cellX > gx then dir = "left"
            elseif npc.cellY < gy then dir = "down"
            else dir = "up" end
            npc.facing = dir
            npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
            npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
            local stepLen = p.stepFramesCur or p.stepFrames or 16
            if far > 1 then
              stepLen = math.max(1, math.floor(stepLen / 2))
            end
            npc.stepFrames = stepLen
            npc.moving = true
            npc.progress = 0
            -- Same catch-up as PikachuFollower: this frame's npc:update
            -- already ran, so burn the first step frame now.
            if npc.update then npc:update(ow.map, ow.entities) end
          end
        else
          npc.facing = p.facing or npc.facing
        end
      end
    end
  end

  -- Stock PikachuFollower: only suppress when we are actively drawing trailers
  -- or the player IS the pokemon. Never leave the field with nobody when
  -- pack size is 0 in trainer-walk mode (fallback to stub/vanilla spawn).
  local function captureUpvalue(fn, upvalueName)
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
      return nil, nil
    end
    local i = 1
    while true do
      local name, val = debug.getupvalue(fn, i)
      if not name then break end
      if name == upvalueName then return i, val end
      i = i + 1
    end
    return nil, nil
  end

  local function patchUpvalue(fn, upvalueName, newVal)
    local idx = select(1, captureUpvalue(fn, upvalueName))
    if idx and debug.setupvalue then
      debug.setupvalue(fn, idx, newVal)
      return true
    end
    return false
  end

  local _, prevShouldSpawn = captureUpvalue(PikachuFollower.onMapEntered, "shouldSpawn")
  if not prevShouldSpawn then
    _, prevShouldSpawn = captureUpvalue(PikachuFollower.update, "shouldSpawn")
  end

  local function removeStockPikachu(ow)
    if not ow then return end
    for i = #(ow.npcs or {}), 1, -1 do
      local npc = ow.npcs[i]
      if npc and npc.pikachuFollower then
        table.remove(ow.npcs, i)
        for j, e in ipairs(ow.entities or {}) do
          if e == npc then table.remove(ow.entities, j); break end
        end
      end
    end
  end

  local function newShouldSpawn(game, ow)
    local mode = controlMode(game)
    -- Player-is-pokemon modes must NEVER keep the stock follower — even when
    -- pack size is 0 (save often has pack + pokepcFollowerCount=0). Otherwise
    -- the leader sprite and stock SPRITE_PIKACHU show as the same mon.
    if mode == "pokemon" or mode == "lead_trainer" or mode == "pack" then
      return false
    end
    if mode == "follow" and followerCount(game) > 0 then
      return false
    end
    if type(prevShouldSpawn) == "function" then
      return prevShouldSpawn(game, ow)
    end
    return false
  end

  patchUpvalue(PikachuFollower.update, "shouldSpawn", newShouldSpawn)
  patchUpvalue(PikachuFollower.onMapEntered, "shouldSpawn", newShouldSpawn)

  local origFollowerUpdate = PikachuFollower.update
  PikachuFollower.update = function(game, ow, ...)
    local result = origFollowerUpdate(game, ow, ...)
    if isPokemonFront(game) then pcall(removeStockPikachu, ow) end
    pcall(syncPlayerControlVisual, game, ow)
    pcall(syncTrailers, game, ow)
    return result
  end

  local origOnMap = PikachuFollower.onMapEntered
  PikachuFollower.onMapEntered = function(game, ow, opts)
    origOnMap(game, ow, opts)
    local mode = controlMode(game)
    if mode == "pokemon" or mode == "lead_trainer" or mode == "pack"
       or (mode == "follow" and followerCount(game) > 0) then
      pcall(removeStockPikachu, ow)
      pcall(removeTrailers, ow)
    end
    pcall(syncPlayerControlVisual, game, ow)
    pcall(syncTrailers, game, ow)
  end

  -- Pull FOLLOWERS_EX option values into save so stuck pokepcFollowerCount=0
  -- cannot blank the pack after we suppress stock spawn.
  local function alignSaveFromOptions(game)
    game = game or Game
    if not (game and game.save) then return end
    local n = tonumber(opt("follower_count", 1))
    if type(n) == "number" then
      setFollowerCount(game, n)
    end
    local savedMode = game.save.pokepcControlMode
    if type(savedMode) ~= "string" or savedMode == "" then
      setControlMode(game, tostring(opt("control_mode", "follow")))
    end
  end

  mod.events:on("map.entered", function()
    local game, ow = Game, Game and Game.overworld
    pcall(syncPlayerControlVisual, game, ow)
    pcall(syncTrailers, game, ow)
  end)
  mod.events:on("game.ready", function()
    alignSaveFromOptions(Game)
    pcall(syncPlayerControlVisual, Game, Game and Game.overworld)
    pcall(syncTrailers, Game, Game and Game.overworld)
  end)
  mod.events:on("world.stepped", function()
    pcall(syncTrailers, Game, Game and Game.overworld)
  end)

  -- ------- Resolve / draw (pokemon followers only — trainer uses engine OBP)
  local origResolveImage = SpriteRenderer.resolveImage
  SpriteRenderer.resolveImage = function(self, ...)
    local id = self.def and self.def.id
    if id == "SPRITE_POKEPC_MON" or id == "SPRITE_PLAYER_POKEMON"
       or id == "SPRITE_PIKACHU" then
      local species = self.def.image
        and self.def.image:match("follower_([%w_]+)%.png")
      local shiny = self.def and self.def.pokepcShiny
      if not species then
        local mon = getLeaderMon(Game)
        species = mon and mon.species or "CHARMANDER"
        if shiny == nil and mon and Stats.isShiny then
          shiny = Stats.isShiny(mon.dvs)
        end
      end
      return getFollowerImage(species, shiny)
    end
    return origResolveImage(self, ...)
  end

  local function drawTrailerSparkles(key, x, y, seed)
    local shinyMod = mod:find("SHINY_POKEMON")
    local fn = shinyMod and shinyMod.exports and shinyMod.exports.drawOwFollowerSparkles
    if type(fn) == "function" then
      pcall(fn, key, x, y, seed or 11, 0.95)
    end
  end

  local origSpriteDraw = SpriteRenderer.draw
  function SpriteRenderer:draw(px, py, camX, camY, facing, walkPhase, stepFlip)
    local id = self.def and self.def.id
    if id == "SPRITE_POKEPC_MON" or id == "SPRITE_PLAYER_POKEMON"
        or id == "SPRITE_PIKACHU" then
      local species = self.def.image
        and self.def.image:match("follower_([%w_]+)%.png")
      local shiny = self.def and self.def.pokepcShiny
      if not species then
        local mon = getLeaderMon(Game)
        species = mon and mon.species or "CHARMANDER"
        if shiny == nil and mon and Stats.isShiny then
          shiny = Stats.isShiny(mon.dvs)
        end
      end
      local img = getFollowerImage(species, shiny)
      if img then
        local x = math.floor(px - camX)
        local y = math.floor(py - camY) - 4
        local STAND, WALK = SpriteRenderer.STAND, SpriteRenderer.WALK
        local dirMap = (walkPhase == 1) and WALK or STAND
        local frameIdx = dirMap[facing] or 0
        local quad = self.frames[frameIdx]
        local flip = (facing == "right")
          or (stepFlip and (facing == "up" or facing == "down"))
        PaletteFX.markSpriteRedraw(img, quad, flip and (x + 16) or x, y,
          flip and -1 or 1, nil, false)
        if shiny then
          local key
          if id == "SPRITE_POKEPC_MON" then
            key = "trailer:" .. tostring(self.id or species)
          else
            key = "follower:" .. tostring(species)
          end
          drawTrailerSparkles(key, x + 8, y + 4, 11)
        end
        return
      end
    end
    return origSpriteDraw(self, px, py, camX, camY, facing, walkPhase, stepFlip)
  end

  -- ------- Battle / Trainer ID
  -- Trainer-pic substitute uses the LEADER flag only. Battle send-out still
  -- uses Party.firstHealthy — these must stay independent.
  local function leaderForTrainerPic(game)
    game = game or Game
    local save = game and game.save
    local meta = save and save.pokepcLeader
    if meta and meta.source == "party" and save.party then
      local mon = save.party[meta.index]
      if mon then return mon end
    end
    if meta and meta.source == "box" then
      return (getLeaderMon(game))
    end
    return (getLeaderMon(game))
  end

  mod.hooks:wrap("player.sprite", function(next, path, ctx)
    path = next(path, ctx)
    if not ctx or not isPokemonFront(Game) or ctx.demo then return path end
    local mon = leaderForTrainerPic(Game)
    if not mon then return path end
    local data = ctx.data or (Game and Game.data)
    if not data then return path end
    if ctx.kind == "battle" and ctx.side == "back" then
      local p, tc = Sprites.path(data, mon.species, "back", {
        mon = mon, kind = "battle",
      })
      if p then ctx.trueColor = tc and true or false; return p end
    elseif ctx.kind == "trainer_card" then
      local p, tc = Sprites.path(data, mon.species, "front", {
        mon = mon, kind = "summary",
      })
      if p then ctx.trueColor = tc and true or false; return p end
    end
    return path
  end)

  -- Battle intro back-pic = LEADER (via player.sprite hook above).
  -- Do NOT clear playerBackPic here and do NOT reorder party send-out:
  -- send-out stays Party.firstHealthy; leader only replaces the trainer pic.

  -- Party / PC leader UI: FOLLOWERS_EX mod (keeps sprite-pack credit clean).

  -- Yellow starter renames
  if GameVersion.isYellow() then
    mod.content.strings:override("PIKACHU", "CHARMANDER")
    local origNewWild = BattleState.newWild
    BattleState.newWild = function(game, species, level, ...)
      if species == "PIKACHU" and level == 5 then species = "CHARMANDER" end
      return origNewWild(game, species, level, ...)
    end
  end

  PikachuFollower.starterInParty = function(save, needHealthy)
    for _, mon in ipairs(save.party or {}) do
      if not needHealthy or (mon.hp or 0) > 0 then return mon end
    end
    return nil
  end

  local api = {
    version = "1.5.0-ex",
    controlMode = controlMode,
    setControlMode = setControlMode,
    getActiveFollowerMon = getActiveFollowerMon,
    getLeaderMon = getLeaderMon,
    setLeaderParty = setLeaderParty,
    setLeaderBox = setLeaderBox,
    followerCount = followerCount,
    setFollowerCount = setFollowerCount,
    syncPlayerControlVisual = syncPlayerControlVisual,
    syncTrailers = syncTrailers,
    alignSaveFromOptions = alignSaveFromOptions,
    syncAll = function(game, ow)
      pcall(syncPlayerControlVisual, game, ow)
      pcall(syncTrailers, game, ow)
    end,
    _followersExControlEngine = true,
  }
  for k, v in pairs(api) do
    mod.exports[k] = v
  end
  if assetMod then
    assetMod.exports = assetMod.exports or {}
    for k, v in pairs(api) do assetMod.exports[k] = v end
  end
  -- Game.save may already exist during soft-reload; align immediately.
  pcall(alignSaveFromOptions, Game)
  print("[FOLLOWERS_EX] ControlEngine ready")
  return api
end
