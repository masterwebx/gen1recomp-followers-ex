-- Followers EX: control modes / pack / leaders + wilds follower sheets.
-- Depends on PokePCFollowers_VoxelMerge (Antigravity sprite pack).
return function(mod)
  local Game = require("src.core.Game")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")
  local PartyMenu = require("src.ui.PartyMenu")
  local Boxes = require("src.pokemon.Boxes")
  local Screens = require("src.ui.Screens")
  local SpriteRenderer = require("src.render.SpriteRenderer")

  local WILDS_ID = "overworld_wild_spawns"
  local FOLLOWERS_ID = "PokePCFollowers_VoxelMerge"

  local function poke()
    return mod:find(FOLLOWERS_ID)
  end

  local function exports()
    local p = poke()
    return p and p.exports or {}
  end

  mod.options:define({
    {
      key = "control_mode",
      type = "choice",
      label = "CONTROL MODE",
      default = "follow",
      choices = {
        { "Trainer", "follow" },
        { "Pokemon", "pokemon" },
      },
      help = "Who you control. Leader via LEADER / BOX LEADER.",
    },
    {
      key = "trainer_follows",
      type = "toggle",
      label = "TRAINER FOLLOWS",
      default = false,
      help = "When ON, you control a Pokemon and the trainer trails behind.",
    },
    {
      key = "follower_count",
      type = "choice",
      label = "FOLLOWERS",
      default = 1,
      choices = {
        { "0", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 },
        { "4", 4 }, { "5", 5 }, { "6", 6 },
      },
      help = "How many party mons trail (excludes the controlled leader).",
    },
    {
      key = "show_in_menu",
      type = "toggle",
      label = "SHOW IN MENU",
      default = false,
      help = "Add FOLLOWERS EX to the Start menu.",
    },
    {
      key = "wilds_follower_sprites",
      type = "toggle",
      label = "WILDS SPRITES",
      default = true,
      help = "Use PokÃ©PC follower walk sheets for Wilds of Kanto overworld spawns.",
    },
  })

  local optCache = {}
  local function optBool(key, default)
    if optCache[key] ~= nil then return optCache[key] end
    local ok, got = pcall(mod.options.get, mod.options, key)
    optCache[key] = (ok and got ~= nil) and (got and true or false) or default
    return optCache[key]
  end

  local function optChoice(key, default)
    if optCache[key] ~= nil then return optCache[key] end
    local ok, got = pcall(mod.options.get, mod.options, key)
    optCache[key] = (ok and got ~= nil) and got or default
    return optCache[key]
  end

  local function persistOpt(key, value, game)
    optCache[key] = value
    pcall(function() mod.options:set(key, value) end)
    if game and game.save then
      game.save.options = game.save.options or {}
      game.save.options.modOptions = game.save.options.modOptions or {}
      game.save.options.modOptions[mod.id] =
        game.save.options.modOptions[mod.id] or {}
      game.save.options.modOptions[mod.id][key] = value
    end
    if game and game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      game.mods.modOptions[mod.id] = game.mods.modOptions[mod.id] or {}
      game.mods.modOptions[mod.id][key] = value
    end
    if game and game.writeOptions then pcall(game.writeOptions, game) end
  end

  local applyingUi = false

  local function liveMode(game)
    local ex = exports()
    if type(ex.controlMode) == "function" then
      local m = ex.controlMode(game or Game)
      if type(m) == "string" and m ~= "" then return m end
    end
    local saved = game and game.save and game.save.pokepcControlMode
    if type(saved) == "string" and saved ~= "" then return saved end
    return tostring(optChoice("control_mode", "follow"))
  end

  -- Mirror trainer_follows from the real engine mode (party / OPTIONS).
  local function syncTrainerFollowsFromMode(mode, game)
    local follows = (mode == "lead_trainer")
    if optCache.trainer_follows == follows then return end
    persistOpt("trainer_follows", follows, game)
  end

  -- Map CONTROL MODE (trainer/pokemon) + TRAINER FOLLOWS onto engine modes.
  local function applyControlUi(game, who, trainerFollows)
    local ex = exports()
    local g = game or Game
    local mode
    if who == "trainer" then
      mode = "follow"
      trainerFollows = false
    elseif trainerFollows then
      mode = "lead_trainer"
    else
      -- Preserve pack if already packing; otherwise solo BE MON.
      mode = (liveMode(g) == "pack") and "pack" or "pokemon"
    end
    applyingUi = true
    persistOpt("trainer_follows", trainerFollows and true or false, g)
    if type(ex.setControlMode) == "function" then
      pcall(ex.setControlMode, g, mode)
    else
      persistOpt("control_mode", mode, g)
    end
    optCache.control_mode = mode
    applyingUi = false
    pcall(function()
      if ex.syncAll then ex.syncAll(g, g and g.overworld) end
    end)
  end

  local function setOpt(key, value, game)
    local ex = exports()
    local g = game or Game
    if key == "control_mode" then
      local who = (value == "follow" or value == "trainer") and "trainer" or "pokemon"
      local follows = (who == "pokemon") and (
        liveMode(g) == "lead_trainer" or optBool("trainer_follows", false))
      applyControlUi(g, who, follows)
      return
    end
    if key == "trainer_follows" then
      local follows = value and true or false
      -- YES forces Pokemon control; NO leaves who as-is (trainer stays trainer).
      local who = follows and "pokemon" or (
        liveMode(g) == "follow" and "trainer" or "pokemon")
      applyControlUi(g, who, follows)
      return
    end
    persistOpt(key, value, g)
    if key == "follower_count" and type(ex.setFollowerCount) == "function" then
      pcall(ex.setFollowerCount, g, value)
    end
    pcall(function()
      if ex.syncAll then ex.syncAll(g, g and g.overworld) end
    end)
  end

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    optCache[payload.key] = payload.value
    if applyingUi then return end
    local ex = exports()
    if payload.key == "trainer_follows" then
      local follows = payload.value and true or false
      local mode = liveMode(Game)
      if follows and mode ~= "lead_trainer" then
        applyControlUi(Game, "pokemon", true)
      elseif not follows and mode == "lead_trainer" then
        applyControlUi(Game, "pokemon", false)
      end
      return
    end
    if payload.key == "control_mode" then
      -- Party / setControlMode writes full engine modes; just mirror TRAINER FOLLOWS.
      if payload.value == "lead_trainer" or payload.value == "pack"
          or payload.value == "pokemon" or payload.value == "follow" then
        syncTrainerFollowsFromMode(payload.value, Game)
        return
      end
      if payload.value == "trainer" then
        applyControlUi(Game, "trainer", false)
      end
      return
    end
    if payload.key == "follower_count" and type(ex.setFollowerCount) == "function" then
      ex.setFollowerCount(Game, payload.value)
    end
    pcall(function()
      if ex.syncAll then ex.syncAll(Game, Game and Game.overworld) end
    end)
  end)

  -- Keep OPTIONS rows in sync when party menu changes modes.
  mod.events:once("mods.loaded", function()
    local p = poke()
    local ex = p and p.exports
    if not (ex and type(ex.setControlMode) == "function") then return end
    if ex._followersExModeWrapped then return end
    local orig = ex.setControlMode
    ex.setControlMode = function(game, mode)
      orig(game, mode)
      optCache.control_mode = mode
      if not applyingUi then
        syncTrainerFollowsFromMode(mode, game)
      end
    end
    ex._followersExModeWrapped = true
  end)

  local function sync(game)
    local ex = exports()
    local ow = game and game.overworld
    if type(ex.syncPlayerControlVisual) == "function" then
      pcall(ex.syncPlayerControlVisual, game, ow)
    end
    if type(ex.syncTrailers) == "function" then
      pcall(ex.syncTrailers, game, ow)
    end
  end

  local function hasLabel(items, needle)
    for _, it in ipairs(items or {}) do
      if tostring(it.label or ""):find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local function menuItems(menu)
    if not menu then return nil end
    return menu.items or menu.rows or menu.entries
  end

  local function injectBoxLeader(menu, game)
    local items = menuItems(menu)
    if type(items) ~= "table" then return menu end
    if hasLabel(items, "BOX LEADER") then return menu end

    -- Bill's PC draws a "What?" chrome over the bottom rows. Insert ABOVE
    -- PRINT BOX / SEE YA so BOX LEADER stays visible on screen.
    local idx = #items + 1
    for i, it in ipairs(items) do
      local lab = tostring(it.label or "")
      if lab:find("PRINT", 1, true) or lab:find("SEE YA", 1, true) then
        idx = i
        break
      end
    end
    if idx > #items then idx = #items end
    if idx < 1 then idx = 1 end

    table.insert(items, idx, {
      label = "BOX LEADER",
      keepOpen = true,
      onSelect = function()
        local ex = exports()
        Boxes.ensure(game.save)
        local boxNum = game.save.currentBox or 1
        local box = Boxes.active(game.save)
        if not box or #box == 0 then
          game.stack:push(TextBox.new(game,
            Strings("What? There are\nno POKÃ©MON here!")))
          return
        end
        local rows = {}
        for i, mon in ipairs(box) do
          local def = game.data.pokemon[mon.species]
          local name = mon.nickname or (def and def.name) or "?"
          rows[#rows + 1] = {
            label = Strings("%s :L%d", name, mon.level or 1),
            value = i,
          }
        end
        game.stack:push(ListMenu.new(game, Strings("BOX LEADER"), rows, {
          onChoose = function(item)
            local mon = box[item.value]
            if not mon then return end
            if type(ex.setLeaderBox) == "function" then
              ex.setLeaderBox(game, boxNum, item.value)
            end
            sync(game)
            local Sound = require("src.core.Sound")
            Sound.play(game.data, "Swap")
            local def = game.data.pokemon[mon.species]
            local name = mon.nickname or (def and def.name) or "?"
            game.stack:push(TextBox.new(game,
              Strings("%s is now\nthe leader!", name)))
          end,
        }))
      end,
    })
    if menu.th then menu.th = #items * 2 + 2 end
    return menu
  end

  -- Patch the module + Screens.push (Bill's PC uses Screens.push("BoxMenu")).
  -- Do NOT screens:register("BoxMenu") â€” overwriting the builtin can fail load.
  do
    local BoxMenu = require("src.ui.BoxMenu")
    local origBoxNew = BoxMenu._followersExOrigNew or BoxMenu.new
    BoxMenu._followersExOrigNew = origBoxNew
    function BoxMenu.new(game, ...)
      return injectBoxLeader(origBoxNew(game, ...), game)
    end
  end

  if not Screens._followersExPushWrapped then
    local origPush = Screens.push
    function Screens.push(game, id, ...)
      local inst = origPush(game, id, ...)
      if id == "BoxMenu" or (inst and inst.screenId == "BoxMenu") then
        pcall(injectBoxLeader, inst, game)
      end
      return inst
    end
    Screens._followersExPushWrapped = true
  end

  -- Also catch direct stack:push of a BoxMenu instance.
  mod.events:on("game.ready", function()
    local g = Game
    if not (g and g.stack and not g.stack._followersExWrapped) then return end
    local stack = g.stack
    local origStackPush = stack.push
    function stack:push(state, ...)
      local ret = origStackPush(self, state, ...)
      if state and (state.screenId == "BoxMenu"
          or (state.items and hasLabel(state.items, "WITHDRAW"))) then
        pcall(injectBoxLeader, state, g)
      end
      return ret
    end
    stack._followersExWrapped = true
  end)

  -- Left/Right on PACK N in the party submenu.
  if not PartyMenu._followersExPackLr then
    local origUpdate = PartyMenu.update
    function PartyMenu:update(dt)
      if self.submenu and self.subItems then
        local entry = self.subItems[self.subIndex]
        if entry and entry.pokepcPackAdjust then
          local input = self.game.input
          if input:wasPressed("left") then
            entry.onAdjust(self.game, -1, self)
            return
          elseif input:wasPressed("right") then
            entry.onAdjust(self.game, 1, self)
            return
          end
        end
      end
      return origUpdate(self, dt)
    end
    PartyMenu._followersExPackLr = true
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    items = next(game, items, mon, ctx) or items
    if not items or not mon or not game or (ctx and ctx.battle) then
      return items
    end
    local ex = exports()
    if type(ex.getLeaderMon) ~= "function" then return items end
    if hasLabel(items, "BE MON") or hasLabel(items, "PACK") then
      return items
    end

    local party = game.save.party or {}
    local partyIndex = nil
    for i, pmon in ipairs(party) do
      if pmon == mon then partyIndex = i; break end
    end
    if not partyIndex then
      -- Fallback if PartyMenu ever passes a non-identical table.
      for i, pmon in ipairs(party) do
        if pmon and mon and pmon.species == mon.species
            and pmon.level == mon.level
            and pmon.nickname == mon.nickname then
          partyIndex = i
          break
        end
      end
    end
    partyIndex = partyIndex or 1
    local leader = ex.getLeaderMon(game)
    local isLeader = leader == mon
      or (leader and mon and leader.species == mon.species
          and leader.level == mon.level and leader.nickname == mon.nickname
          and game.save.pokepcLeader and game.save.pokepcLeader.source == "party"
          and game.save.pokepcLeader.index == partyIndex)
    local mode = type(ex.controlMode) == "function" and ex.controlMode(game) or "follow"

    local function packLabel()
      local n = type(ex.followerCount) == "function" and ex.followerCount(game) or 1
      local m = type(ex.controlMode) == "function" and ex.controlMode(game) or mode
      local mark = (m == "pack") and "*" or ""
      return Strings("PACK %d%s", n, mark)
    end

    -- Already the leader: no LEADER row. Control mode does not clear / replace
    -- the leader flag â€” both read pokepcLeader.
    if not isLeader then
      table.insert(items, {
        label = Strings("LEADER"),
        onSelect = function()
          if type(ex.setLeaderParty) == "function" then
            ex.setLeaderParty(game, partyIndex)
          end
          -- Leader flag only; leave control mode as-is (trainer vs pokemon).
          pcall(function()
            if ex.syncAll then ex.syncAll(game, game.overworld) end
          end)
          sync(game)
          local Sound = require("src.core.Sound")
          Sound.play(game.data, "Swap")
          local def = game.data.pokemon[mon.species]
          local name = mon.nickname or (def and def.name) or mon.species
          game.stack:push(TextBox.new(game,
            Strings("%s is now\nthe leader!", name)))
        end,
      })
    end

    if isLeader then
      -- Hide the active mode so the menu only lists switches.
      if mode ~= "follow" then
        table.insert(items, {
          label = Strings("TRAINER"),
          onSelect = function()
            if ex.setControlMode then ex.setControlMode(game, "follow") end
            sync(game)
            game.stack:push(TextBox.new(game, Strings("You are the\ntrainer again!")))
          end,
        })
      end
      if mode ~= "pokemon" then
        table.insert(items, {
          label = Strings("BE MON"),
          onSelect = function()
            if ex.setControlMode then ex.setControlMode(game, "pokemon") end
            sync(game)
            game.stack:push(TextBox.new(game,
              Strings("You are now\nthe POKÃ©MON!\f(solo)")))
          end,
        })
      end
      if mode ~= "lead_trainer" then
        table.insert(items, {
          label = Strings("+TRAINER"),
          onSelect = function()
            if ex.setControlMode then ex.setControlMode(game, "lead_trainer") end
            sync(game)
            game.stack:push(TextBox.new(game,
              Strings("POKÃ©MON leads!\nTrainer at back.")))
          end,
        })
      end
      if mode ~= "pack" then
        table.insert(items, {
          label = packLabel(),
          pokepcPackAdjust = true,
          onAdjust = function(g, delta, menu)
            local n = (type(ex.followerCount) == "function"
              and ex.followerCount(g) or 1) + delta
            if ex.setFollowerCount then ex.setFollowerCount(g, n) end
            local m = type(ex.controlMode) == "function" and ex.controlMode(g) or "follow"
            if m ~= "lead_trainer" and m ~= "follow" then
              if ex.setControlMode then
                local nn = type(ex.followerCount) == "function" and ex.followerCount(g) or n
                ex.setControlMode(g, nn > 0 and "pack" or "pokemon")
              end
            end
            for _, it in ipairs(menu.subItems or {}) do
              if it.pokepcPackAdjust then it.label = packLabel() end
            end
            local Sound = require("src.core.Sound")
            Sound.play(g.data, "Press_AB")
            sync(g)
          end,
          onSelect = function()
            if type(ex.followerCount) == "function" and ex.followerCount(game) < 1
               and ex.setFollowerCount then
              ex.setFollowerCount(game, 1)
            end
            if ex.setControlMode then ex.setControlMode(game, "pack") end
            sync(game)
            game.stack:push(TextBox.new(game,
              Strings("POKÃ©MON leads!\n%d follow. â—€â–¶",
                type(ex.followerCount) == "function" and ex.followerCount(game) or 1)))
          end,
        })
      end
    end
    return items
  end)

  -- ------- Wilds follower sheets (merged from WILDS_FOLLOWER_SPRITES)
  local function fsExists(path)
    if type(path) ~= "string" or path == "" then return false end
    local fs = love and love.filesystem
    if not (fs and fs.getInfo) then return false end
    local ok, info = pcall(fs.getInfo, path)
    return ok and info ~= nil
  end

  local function followerRoot()
    local def = mod.content.sprites:get("SPRITE_PIKACHU")
    local img = def and def.image
    if type(img) == "string" then
      local root = img:match("^(.-)/assets/sprites/")
      if root and fsExists(root .. "/assets/sprites/follower_CHARMANDER.png") then
        return root
      end
    end
    for _, root in ipairs({
      "mods/PokePCFollowers-main",
      "mods/PokePCFollowers_VoxelMerge",
      "mods/PokePCFollowers",
    }) do
      if fsExists(root .. "/assets/sprites/follower_CHARMANDER.png") then
        return root
      end
    end
    local p = poke()
    if p and p.path and fsExists(p.path .. "/assets/sprites/follower_CHARMANDER.png") then
      return p.path
    end
    return nil
  end

  local function followerPath(root, species)
    return root .. "/assets/sprites/follower_" .. tostring(species) .. ".png"
  end

  local function walkPhaseOf(entity)
    if not entity or not entity.moving then return 0 end
    local m = entity.movement
    local dur = (m and m.duration) or 0.28
    if dur <= 0 then return 0 end
    local t = ((m and m.progress) or 0) / dur
    return (t >= 0.25 and t < 0.75) and 1 or 0
  end

  local function stepFlipOf(entity)
    local x = entity and entity.cellX or 0
    local y = entity and entity.cellY or 0
    return ((x + y) % 2) == 1
  end

  local function applyFollowerSprite(entity, root)
    if not entity or entity.hiddenEncounter or not entity.visibleSprite then
      return false
    end
    local species = entity.species
    if not species then return false end
    local path = followerPath(root, species)
    if not fsExists(path) then return false end

    local def = {
      image = path, frames = 6, walker = true, trueColor = true,
      id = "SPRITE_OW_WILD_" .. tostring(species),
    }
    local ok, sprite = pcall(SpriteRenderer.new, def, entity.spawnId or entity.id)
    if not ok or not sprite then return false end

    entity.sprite = sprite
    entity.spriteId = def.id
    entity.usingFollowerSprite = true
    entity.usingFallback = false
    entity.final2DScale = 1
    entity.visualScale = 1
    entity.voxelScale = 1
    entity.scaleInfo = {
      scale = 1, final2DScale = 1, contentW = 16, contentH = 16,
      offsetX = 0, offsetY = 0, imageW = 16, imageH = 96,
      renderedW = 16, renderedH = 16, originalW = 16, originalH = 96,
      logicalFootprintTiles = 1, grassOcclusionHeight = 0,
    }
    entity.grassOcclusionHeight = 0
    if entity.entityPhase == "FALLBACK_LOADED" or entity.entityPhase == "CREATING" then
      entity.entityPhase = "REAL_ASSET_LOADED"
    end

    local origPose = entity.pose
    function entity:pose()
      local spriteObj, px, py, facing, _, _, hop = origPose(self)
      return spriteObj, px, py, facing, walkPhaseOf(self), stepFlipOf(self), hop
    end

    function entity:_drawScaledSprite(camX, camY, opacity)
      local spriteObj, px, py, facing, phase, flip = self:pose()
      if not spriteObj then return end
      opacity = opacity or 1
      if opacity < 1 and love and love.graphics and love.graphics.setColor then
        love.graphics.setColor(1, 1, 1, opacity)
        spriteObj:draw(px, py, camX, camY, facing, phase, flip)
        love.graphics.setColor(1, 1, 1, 1)
      else
        spriteObj:draw(px, py, camX, camY, facing, phase, flip)
      end
    end
    return true
  end

  -- Dramatic Shape draws tall grass AFTER billboards. Raise visualY so grass
  -- only covers feet (was previously patched into Wilds spawn_render).
  local VOXEL_GRASS_LIFT = 8
  local function applyVoxelGrassLift(entity)
    if not entity or entity._followersExGrassLift then return end
    if type(entity.pose) ~= "function" then return end
    local prev = entity.pose
    function entity:pose()
      local spriteObj, px, py, facing, phase, flip, hop = prev(self)
      if spriteObj and self.inGrassOverlay then
        local voxelOn = self.voxelRegistered
          or (mod:find("DRAMATIC_SHAPE") ~= nil)
        if voxelOn and type(py) == "number" then
          py = py - VOXEL_GRASS_LIFT
        end
      end
      return spriteObj, px, py, facing, phase, flip, hop
    end
    entity._followersExGrassLift = true
  end

  local function installWildsFollowerSprites()
    -- Prefer not double-wrapping if the standalone mod is still on.
    if mod:find("WILDS_FOLLOWER_SPRITES") then
      mod.log:info("WILDS_FOLLOWER_SPRITES still loaded â€” skip merge wrap")
      return
    end

    local wilds = mod:find(WILDS_ID)
    local render = wilds and wilds.exports and wilds.exports.render
    if not render then
      mod.log:warn("%s not ready for wilds follower sheets / grass lift", WILDS_ID)
      return
    end

    local root = nil
    if optBool("wilds_follower_sprites", true) then
      root = followerRoot()
      if not root then
        mod.log:warn("PokÃ©PCFollowers sprite root not found for wilds sheets")
      else
        local patched = 0
        local pokemon = mod.content.pokemon
        if pokemon and pokemon.each then
          for speciesId in pokemon:each() do
            local path = followerPath(root, speciesId)
            if fsExists(path) then
              local spriteId = "SPRITE_OW_WILD_" .. tostring(speciesId)
              local ok = pcall(function()
                mod.content.sprites:patch(spriteId, {
                  image = path, frames = 6, walker = true, trueColor = true,
                })
              end)
              if ok then patched = patched + 1 end
            end
          end
        end
        mod.log:info("patched %d wild OW sprites to follower sheets", patched)

        if not render._followersExCandidates then
          local origCandidates = render.assetCandidates
          function render:assetCandidates(speciesId, game, mon)
            local candidates, monOut = origCandidates(self, speciesId, game, mon)
            if optBool("wilds_follower_sprites", true) then
              local path = followerPath(root, speciesId)
              if fsExists(path) then
                table.insert(candidates, 1, {
                  path = path, source = "follower_sheet",
                })
              end
            end
            return candidates, monOut
          end
          render._followersExCandidates = true
        end

        if render.invalidateAssetCache then
          pcall(render.invalidateAssetCache, render)
        end
      end
    end

    if not render._followersExMake then
      local origMakeEntity = render.makeEntity
      function render:makeEntity(game, record)
        local entity = origMakeEntity(self, game, record)
        if optBool("wilds_follower_sprites", true) and root then
          pcall(applyFollowerSprite, entity, root)
        end
        -- Always: voxel grass lift (independent of sheet swap).
        pcall(applyVoxelGrassLift, entity)
        local shiny = mod:find("SHINY_POKEMON")
        if shiny and shiny.exports and shiny.exports.onWildEntity then
          pcall(shiny.exports.onWildEntity, entity, record)
        end
        return entity
      end
      render._followersExMake = true
    end
  end

  installWildsFollowerSprites()
  mod.events:on("game.ready", installWildsFollowerSprites)
  mod.events:on("mods.loaded", installWildsFollowerSprites)

  -- OPTIONS submenu (QoL-style OPEN row), same pattern as RUN MODE / SHINY.
  local FOLLOWERS_SCREEN = "FollowersExOptions"

  local function makeFollowersScreen(game)
    local OptionRows = require("src.ui.OptionRows")
    local rows = {
      {
        label = "CONTROL MODE",
        value = function()
          return liveMode(game) == "follow" and "TRAINER" or "POKEMON"
        end,
        step = function(g)
          if liveMode(g) == "follow" then
            applyControlUi(g, "pokemon", optBool("trainer_follows", false))
          else
            applyControlUi(g, "trainer", false)
          end
        end,
      },
      {
        label = "TRAINER FOLLOWS",
        value = function()
          return (liveMode(game) == "lead_trainer"
            or optBool("trainer_follows", false)) and "YES" or "NO"
        end,
        step = function(g)
          local on = not (liveMode(g) == "lead_trainer"
            or optBool("trainer_follows", false))
          setOpt("trainer_follows", on, g)
        end,
      },
      {
        label = "FOLLOWERS",
        value = function()
          local ex = exports()
          local n = type(ex.followerCount) == "function" and ex.followerCount(game)
          if n == nil then n = tonumber(optChoice("follower_count", 1)) or 1 end
          return tostring(n)
        end,
        step = function(g)
          local ex = exports()
          local n = type(ex.followerCount) == "function" and ex.followerCount(g)
          if n == nil then n = tonumber(optChoice("follower_count", 1)) or 1 end
          n = (tonumber(n) or 1) + 1
          if n > 6 then n = 0 end
          setOpt("follower_count", n, g)
        end,
      },
      {
        label = "SHOW IN MENU",
        value = function()
          return optBool("show_in_menu", false) and "ON" or "OFF"
        end,
        step = function(g)
          setOpt("show_in_menu", not optBool("show_in_menu", false), g)
        end,
      },
      {
        label = "WILDS SPRITES",
        value = function()
          return optBool("wilds_follower_sprites", true) and "ON" or "OFF"
        end,
        step = function(g)
          setOpt("wilds_follower_sprites",
            not optBool("wilds_follower_sprites", true), g)
        end,
      },
    }
    local screen = {
      game = game, rows = rows, index = 1, scroll = 0, isOpaque = true,
    }
    function screen:sgbPalettes(g)
      return require("src.render.PaletteFX").wholeNamed(g.data, "MEWMON")
    end
    function screen:update()
      local input = self.game.input
      if input:wasPressed("up") then
        self.index = (self.index - 2) % #self.rows + 1
      elseif input:wasPressed("down") then
        self.index = self.index % #self.rows + 1
      elseif input:wasPressed("left") or input:wasPressed("right")
          or input:wasPressed("a") then
        local row = self.rows[self.index]
        if row and row.step then row.step(self.game) end
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      end
      self.scroll = OptionRows.clampScroll(
        self.index, self.scroll, #self.rows, nil)
    end
    function screen:draw()
      OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                      "A/â—€â–¶:CHANGE B:DONE")
    end
    return screen
  end

  mod.content.screens:register(FOLLOWERS_SCREEN, { new = makeFollowersScreen })

  mod.events:once("mods.loaded", function()
    local ManagerState = require("src.mods.ManagerState")
    local routes = rawget(ManagerState, "__modOptionScreenRoutes")
    if not routes then
      routes = {}
      local openOptions = ManagerState.openOptions
      ManagerState.openOptions = function(self, manifest)
        local screenId = manifest and routes[manifest.id]
        if screenId then
          return require("src.ui.Screens").push(self.game, screenId)
        end
        return openOptions(self, manifest)
      end
      ManagerState.__modOptionScreenRoutes = routes
    end
    routes[mod.id] = FOLLOWERS_SCREEN
  end)

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    local row = {
      id = mod.id .. ":open",
      label = "FOLLOWERS EX",
      value = function() return "OPEN" end,
      activate = function(g)
        require("src.ui.Screens").push(g, FOLLOWERS_SCREEN)
      end,
    }
    if mod.ui and type(mod.ui.insertBefore) == "function" then
      return mod.ui.insertBefore(out, "MODS", row)
    end
    out[#out + 1] = row
    return out
  end)

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items
    if not optBool("show_in_menu", false) then return items end
    if hasLabel(items, "FLL EX") then return items end
    table.insert(items, {
      label = Strings("FLL EX"),
      onSelect = function()
        Screens.push(game, FOLLOWERS_SCREEN)
      end,
    })
    return items
  end)

  mod.exports.version = "1.0.1"
  mod.log:info("FOLLOWERS_EX 1.0.1")
end

