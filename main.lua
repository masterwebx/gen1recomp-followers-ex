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
        { "Trainer (pokemon follow)", "follow" },
        { "Be the Pokemon", "pokemon" },
        { "Pokemon leads, trainer follows", "lead_trainer" },
        { "Pokemon leads, pokemon follow", "pack" },
      },
      help = "Who you control. Leader via LEADER / BOX LEADER.",
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
      key = "wilds_follower_sprites",
      type = "toggle",
      label = "WILDS SPRITES",
      default = true,
      help = "Use PokéPC follower walk sheets for Wilds of Kanto overworld spawns.",
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

  local function setOpt(key, value, game)
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
    local ex = exports()
    local g = game or Game
    if key == "control_mode" and type(ex.setControlMode) == "function" then
      pcall(ex.setControlMode, g, value)
    end
    if key == "follower_count" and type(ex.setFollowerCount) == "function" then
      pcall(ex.setFollowerCount, g, value)
    end
    pcall(function()
      if ex.syncAll then ex.syncAll(g, g and g.overworld) end
    end)
  end

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    optCache = {}
    local ex = exports()
    if payload.key == "control_mode" and type(ex.setControlMode) == "function" then
      ex.setControlMode(Game, payload.value)
    end
    if payload.key == "follower_count" and type(ex.setFollowerCount) == "function" then
      ex.setFollowerCount(Game, payload.value)
    end
    pcall(function()
      if ex.syncAll then ex.syncAll(Game, Game and Game.overworld) end
    end)
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
            Strings("What? There are\nno POKéMON here!")))
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
  -- Do NOT screens:register("BoxMenu") — overwriting the builtin can fail load.
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
    local partyIndex = 1
    for i, pmon in ipairs(party) do
      if pmon == mon then partyIndex = i; break end
    end
    local leader = ex.getLeaderMon(game)
    local isLeader = leader == mon
    local mode = type(ex.controlMode) == "function" and ex.controlMode(game) or "follow"

    local function packLabel()
      local n = type(ex.followerCount) == "function" and ex.followerCount(game) or 1
      local m = type(ex.controlMode) == "function" and ex.controlMode(game) or mode
      local mark = (m == "pack") and "*" or ""
      return Strings("PACK %d%s", n, mark)
    end

    table.insert(items, {
      label = Strings(isLeader and "LEADER!" or "LEADER"),
      onSelect = function()
        if type(ex.setLeaderParty) == "function" then
          ex.setLeaderParty(game, partyIndex)
        end
        sync(game)
        local Sound = require("src.core.Sound")
        Sound.play(game.data, "Swap")
        local def = game.data.pokemon[mon.species]
        local name = mon.nickname or (def and def.name) or mon.species
        game.stack:push(TextBox.new(game,
          Strings("%s is now\nthe leader!", name)))
      end,
    })

    if isLeader then
      table.insert(items, {
        label = Strings(mode == "follow" and "TRAINER*" or "TRAINER"),
        onSelect = function()
          if ex.setControlMode then ex.setControlMode(game, "follow") end
          sync(game)
          game.stack:push(TextBox.new(game, Strings("You are the\ntrainer again!")))
        end,
      })
      table.insert(items, {
        label = Strings(mode == "pokemon" and "BE MON*" or "BE MON"),
        onSelect = function()
          if ex.setControlMode then ex.setControlMode(game, "pokemon") end
          sync(game)
          game.stack:push(TextBox.new(game,
            Strings("You are now\nthe POKéMON!\f(solo)")))
        end,
      })
      table.insert(items, {
        label = Strings(mode == "lead_trainer" and "+TRAINER*" or "+TRAINER"),
        onSelect = function()
          if ex.setControlMode then ex.setControlMode(game, "lead_trainer") end
          sync(game)
          game.stack:push(TextBox.new(game,
            Strings("POKéMON leads!\nTrainer at back.")))
        end,
      })
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
            if it.label and tostring(it.label):find("BE MON", 1, true) then
              local cm = type(ex.controlMode) == "function" and ex.controlMode(g)
              it.label = Strings(cm == "pokemon" and "BE MON*" or "BE MON")
            end
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
            Strings("POKéMON leads!\n%d follow. ◀▶",
              type(ex.followerCount) == "function" and ex.followerCount(game) or 1)))
        end,
      })
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

  local function installWildsFollowerSprites()
    if not optBool("wilds_follower_sprites", true) then return end
    -- Prefer not double-wrapping if the standalone mod is still on.
    if mod:find("WILDS_FOLLOWER_SPRITES") then
      mod.log:info("WILDS_FOLLOWER_SPRITES still loaded — skip merge wrap")
      return
    end
    local root = followerRoot()
    if not root then
      mod.log:warn("PokéPCFollowers sprite root not found for wilds sheets")
      return
    end

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

    local wilds = mod:find(WILDS_ID)
    local render = wilds and wilds.exports and wilds.exports.render
    if not render then
      mod.log:warn("%s not ready for wilds follower sheets", WILDS_ID)
      return
    end

    if not render._followersExCandidates then
      local origCandidates = render.assetCandidates
      function render:assetCandidates(speciesId, game, mon)
        local candidates, monOut = origCandidates(self, speciesId, game, mon)
        if optBool("wilds_follower_sprites", true) then
          local path = followerPath(root, speciesId)
          if fsExists(path) then
            table.insert(candidates, 1, { path = path, source = "follower_sheet" })
          end
        end
        return candidates, monOut
      end
      render._followersExCandidates = true
    end

    if render.invalidateAssetCache then pcall(render.invalidateAssetCache, render) end

    if not render._followersExMake then
      local origMakeEntity = render.makeEntity
      function render:makeEntity(game, record)
        local entity = origMakeEntity(self, game, record)
        if optBool("wilds_follower_sprites", true) then
          pcall(applyFollowerSprite, entity, root)
        end
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
  local MODE_ORDER = { "follow", "pokemon", "lead_trainer", "pack" }
  local MODE_LABEL = {
    follow = "TRAINER",
    pokemon = "BE MON",
    lead_trainer = "+TRAINER",
    pack = "PACK",
  }

  local function makeFollowersScreen(game)
    local OptionRows = require("src.ui.OptionRows")
    local rows = {
      {
        label = "CONTROL MODE",
        value = function()
          local m = optChoice("control_mode", "follow")
          return MODE_LABEL[m] or "TRAINER"
        end,
        step = function(g)
          local cur = optChoice("control_mode", "follow")
          local idx = 1
          for i, k in ipairs(MODE_ORDER) do
            if k == cur then idx = i break end
          end
          idx = (idx % #MODE_ORDER) + 1
          setOpt("control_mode", MODE_ORDER[idx], g)
        end,
      },
      {
        label = "FOLLOWERS",
        value = function()
          return tostring(tonumber(optChoice("follower_count", 1)) or 1)
        end,
        step = function(g)
          local n = tonumber(optChoice("follower_count", 1)) or 1
          n = (n + 1) % 7
          setOpt("follower_count", n, g)
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
                      "A/◀▶:CHANGE B:DONE")
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

  mod.exports.version = "1.0.0"
  mod.log:info("FOLLOWERS_EX 1.0.0")
end
