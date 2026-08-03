-- Followers EX: control modes / pack / leaders (PokePC walker sheets).
-- Depends on PokePCFollowers_VoxelMerge (Antigravity sprite pack).
return function(mod)
  local Game = require("src.core.Game")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")
  local PartyMenu = require("src.ui.PartyMenu")
  local Boxes = require("src.pokemon.Boxes")
  local Screens = require("src.ui.Screens")

  local WILDS_ID = "overworld_wild_spawns"
  local FOLLOWERS_ID = "PokePCFollowers_VoxelMerge"

  -- Local lib loader (same pattern as Hunt Mode).
  local libModules = {}
  local function libRequire(name)
    local hit = libModules[name]
    if hit ~= nil then return hit end
    local source = mod:read("lib/" .. name .. ".lua")
    if not source then
      error("FOLLOWERS_EX: missing lib/" .. name .. ".lua", 0)
    end
    local chunk, err = load(source, "@" .. mod.path .. "/lib/" .. name .. ".lua")
    if not chunk then
      error("FOLLOWERS_EX: " .. name .. " compile: " .. tostring(err), 0)
    end
    hit = chunk()
    libModules[name] = hit
    return hit
  end

  local ControlEngine = libRequire("ControlEngine")
  local WildsExtras = libRequire("WildsExtras")
  local BillboardUvFix = libRequire("BillboardUvFix")
  if type(BillboardUvFix) == "function" then
    BillboardUvFix = BillboardUvFix(mod)
  end

  local function poke()
    return mod:find(FOLLOWERS_ID)
  end

  local function exports()
    local p = poke()
    local ex = p and p.exports or {}
    if type(ex.setFollowerCount) == "function" then return ex end
    -- ControlEngine publishes onto FOLLOWERS_EX.exports when PokePC is a stub.
    if type(mod.exports.setFollowerCount) == "function" then return mod.exports end
    return ex
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
      key = "wilds_town_spawns",
      type = "toggle",
      label = "TOWN SPAWNS",
      default = false,
      help = "Allow wild OW spawns in towns (borrows a nearby route grass table).",
    },
    {
      key = "wilds_grass_lift",
      type = "toggle",
      label = "GRASS LIFT",
      default = false,
      help = "ON = wilds drawn above tall grass; OFF = immersed in grass (Wilds 0.6 mode).",
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
    -- Booleans are never valid choice values (corrupted follower_count etc.).
    if ok and got ~= nil and type(got) ~= "boolean" then
      optCache[key] = got
    else
      optCache[key] = default
    end
    return optCache[key]
  end

  -- Engine mod.options has define/get only — never call options:set.
  local function persistOpt(key, value, game)
    optCache[key] = value
    local g = game or Game
    if g and g.save then
      g.save.options = g.save.options or {}
      g.save.options.modOptions = g.save.options.modOptions or {}
      g.save.options.modOptions[mod.id] =
        g.save.options.modOptions[mod.id] or {}
      g.save.options.modOptions[mod.id][key] = value
    end
    if g and g.mods then
      g.mods.modOptions = g.mods.modOptions or {}
      g.mods.modOptions[mod.id] = g.mods.modOptions[mod.id] or {}
      g.mods.modOptions[mod.id][key] = value
    end
    if g and g.writeOptions then pcall(g.writeOptions, g) end
  end

  local applyingUi = false

  -- Never use bare `and` for counts: missing export yields false, not nil.
  local function liveFollowerCount(game)
    local ex = exports()
    if type(ex.followerCount) == "function" then
      local n = ex.followerCount(game or Game)
      if type(n) == "number" then
        return math.max(0, math.min(6, math.floor(n)))
      end
    end
    local raw = optChoice("follower_count", 1)
    if raw == false or raw == true then raw = nil end
    return math.max(0, math.min(6, tonumber(raw) or 1))
  end

  local function sanitizeFollowerCountOpt(game)
    local ok, got = pcall(mod.options.get, mod.options, "follower_count")
    if ok and type(got) == "boolean" then
      persistOpt("follower_count", 1, game or Game)
      return true
    end
    return false
  end

  local function liveMode(game)
    local ex = exports()
    if type(ex.controlMode) == "function" then
      local m = ex.controlMode(game or Game)
      if type(m) == "string" and m ~= "" then return m end
    end
    local saved = game and game.save and game.save.pokepcControlMode
    if type(saved) == "string" and saved ~= "" then return saved end
    local mode = optChoice("control_mode", "follow")
    if type(mode) ~= "string" or mode == "" then mode = "follow" end
    return mode
  end

  local function pokeReady()
    local ex = exports()
    return type(ex.setFollowerCount) == "function"
      and type(ex.setControlMode) == "function"
      and type(ex.syncAll) == "function"
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
      -- Pokemon control, no trainer NPC: pack trails if FOLLOWERS > 0, else solo.
      mode = (liveFollowerCount(g) > 0) and "pack" or "pokemon"
    end
    applyingUi = true
    persistOpt("trainer_follows", trainerFollows and true or false, g)
    -- Keep OPTIONS choice in sync (follow/pokemon), engine mode on the save.
    persistOpt("control_mode", who == "trainer" and "follow" or "pokemon", g)
    if type(ex.setControlMode) == "function" then
      pcall(ex.setControlMode, g, mode)
    elseif g and g.save then
      g.save.pokepcControlMode = mode
    end
    optCache.control_mode = who == "trainer" and "follow" or "pokemon"
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
    if key == "follower_count" then
      value = math.max(0, math.min(6, math.floor(tonumber(value) or 1)))
    end
    persistOpt(key, value, g)
    if key == "follower_count" and type(ex.setFollowerCount) == "function" then
      pcall(ex.setFollowerCount, g, value)
    end
    pcall(function()
      if type(ex.syncAll) == "function" then ex.syncAll(g, g and g.overworld) end
    end)
  end

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    local val = payload.value
    if payload.key == "follower_count" and type(val) == "boolean" then
      val = 1
      persistOpt("follower_count", val, Game)
    end
    optCache[payload.key] = val
    if applyingUi then return end
    local ex = exports()
    if payload.key == "trainer_follows" then
      local follows = val and true or false
      local mode = liveMode(Game)
      if follows and mode ~= "lead_trainer" then
        applyControlUi(Game, "pokemon", true)
      elseif not follows and mode == "lead_trainer" then
        applyControlUi(Game, "pokemon", false)
      end
      return
    end
    if payload.key == "control_mode" then
      -- OPTIONS choices are follow/pokemon; apply to save + visuals.
      -- lead_trainer/pack are written by party/setControlMode already.
      if val == "trainer" or val == "follow" then
        applyControlUi(Game, "trainer", false)
      elseif val == "pokemon" then
        local follows = liveMode(Game) == "lead_trainer"
          or optBool("trainer_follows", false)
        applyControlUi(Game, "pokemon", follows)
      elseif val == "lead_trainer" or val == "pack" then
        syncTrainerFollowsFromMode(val, Game)
        if type(ex.setControlMode) == "function" then
          pcall(ex.setControlMode, Game, val)
        end
        pcall(function()
          if type(ex.syncAll) == "function" then
            ex.syncAll(Game, Game and Game.overworld)
          end
        end)
      end
      return
    end
    if payload.key == "follower_count" then
      local n = math.max(0, math.min(6, math.floor(tonumber(val) or 1)))
      if type(ex.setFollowerCount) == "function" then
        pcall(ex.setFollowerCount, Game, n)
      elseif Game and Game.save then
        Game.save.pokepcFollowerCount = n
      end
    end
    pcall(function()
      if type(ex.syncAll) == "function" then
        ex.syncAll(Game, Game and Game.overworld)
      end
    end)
  end)

  local controlEngineInstalled = false
  local wildsExtrasInstalled = false

  local function ensureControlEngine()
    if pokeReady() then return true end
    local p = poke()
    if not p then
      mod.log:warn("PokePCFollowers_VoxelMerge missing — sprites/control unavailable")
      return false
    end
    if mod.exports._followersExControlEngine or (p.exports and p.exports._followersExControlEngine) then
      controlEngineInstalled = true
      return pokeReady()
    end
    local ok, err = pcall(ControlEngine, mod, p)
    if not ok then
      mod.log:error("ControlEngine failed: " .. tostring(err))
      return false
    end
    controlEngineInstalled = true
    mod.log:info("ControlEngine installed over PokePC stub (sprite assets from pack)")
    return pokeReady()
  end

  local function ensureWildsExtras()
    if wildsExtrasInstalled then return true end
    local wilds = mod:find(WILDS_ID)
    if not wilds then return false end
    local api = WildsExtras
    if type(api) == "function" then api = api(mod) end
    if type(api) ~= "table" or type(api.install) ~= "function" then
      mod.log:warn("WildsExtras load failed")
      return false
    end
    local ok, result = pcall(api.install, wilds)
    if not ok then
      mod.log:error("WildsExtras install failed: " .. tostring(result))
      return false
    end
    wildsExtrasInstalled = result and true or false
    return wildsExtrasInstalled
  end

  local function wrapControlModeSync()
    local ex = exports()
    if type(ex.setControlMode) ~= "function" then return end
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
  end

  local function warnMissingPoke(game)
    if pokeReady() then return end
    mod.log:warn(
      "PokePCFollowers_VoxelMerge missing — install the Voxel Merge sprite pack")
    if game and game.stack and not game._followersExWarnedStub then
      game._followersExWarnedStub = true
      pcall(function()
        game.stack:push(TextBox.new(game, Strings(
          "FOLLOWERS EX needs\nPokéPC Followers\v(Voxel Merge).\fInstall that pack\nand restart.")))
      end)
    end
  end

  -- ControlEngine MUST install during entry (before content freeze).
  -- mods.loaded fires AFTER registries freeze — sprites:patch would abort install.
  sanitizeFollowerCountOpt(Game)
  if not ensureControlEngine() then
    mod.log:error("ControlEngine failed to install during load")
  end
  wrapControlModeSync()

  -- WildsExtras only wraps runtime methods; safe after freeze.
  mod.events:once("mods.loaded", function()
    sanitizeFollowerCountOpt(Game)
    ensureControlEngine() -- no-op if already ready; safe if sprites patch pcall'd
    ensureWildsExtras()
    wrapControlModeSync()
    if not pokeReady() then warnMissingPoke(Game) end
  end)

  mod.events:on("game.ready", function()
    sanitizeFollowerCountOpt(Game)
    ensureControlEngine()
    ensureWildsExtras()
    wrapControlModeSync()
    warnMissingPoke(Game)
    local ex = exports()
    -- Unstick saves that had pokepcFollowerCount=0 while OPTIONS said 6.
    if type(ex.alignSaveFromOptions) == "function" then
      pcall(ex.alignSaveFromOptions, Game)
    elseif type(ex.setFollowerCount) == "function" then
      pcall(ex.setFollowerCount, Game, liveFollowerCount(Game))
    end
    if type(ex.syncAll) == "function" then
      pcall(ex.syncAll, Game, Game and Game.overworld)
    end
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
    if not pokeReady() then ensureControlEngine() end
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
      local n = liveFollowerCount(game)
      local m = liveMode(game)
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
            local n = liveFollowerCount(g) + delta
            if n < 0 then n = 0 elseif n > 6 then n = 6 end
            setOpt("follower_count", n, g)
            local m = liveMode(g)
            if m ~= "lead_trainer" and m ~= "follow" then
              if ex.setControlMode then
                ex.setControlMode(g, liveFollowerCount(g) > 0 and "pack" or "pokemon")
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
            if liveFollowerCount(game) < 1 then
              setOpt("follower_count", 1, game)
            end
            if ex.setControlMode then ex.setControlMode(game, "pack") end
            sync(game)
            game.stack:push(TextBox.new(game,
              Strings("POKéMON leads!\n%d follow. ◀▶",
                liveFollowerCount(game))))
          end,
        })
      end
    end
    return items
  end)

  -- ------- Wilds OW: PokePC walker sheets + Dramatic Shape UV fix
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
      "mods/PokePCFollowers_VoxelMerge",
      "mods/PokePCFollowers-main",
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

  local function applyPokepcWalkerSprite(entity, root)
    if not entity or entity.hiddenEncounter or entity.visibleSprite == false then
      return false
    end
    local species = entity.species
    if not species or not root then return false end
    local path = followerPath(root, species)
    if not fsExists(path) then return false end

    local SpriteRenderer = require("src.render.SpriteRenderer")
    local def = {
      image = path, frames = 6, walker = true, trueColor = true,
      id = "SPRITE_OW_WILD_" .. tostring(species),
    }
    local ok, sprite = pcall(SpriteRenderer.new, def, entity.spawnId or entity.id)
    if not ok or not sprite then return false end

    entity.sprite = sprite
    entity.legacySprite = sprite
    entity.worldSprite = nil
    entity.usingEnhancedSprite = false
    entity.usingFollowerSprite = true
    entity.spriteId = def.id
    entity.final2DScale = 1
    entity.visualScale = 1
    entity.voxelScale = 1
    -- Keep Wilds immersion height. Forcing 0 made converted spawns sit
    -- above grass while unconverted ones stayed tucked under it.
    local prevOcc = entity.grassOcclusionHeight
      or (entity.scaleInfo and entity.scaleInfo.grassOcclusionHeight)
    local occ = (type(prevOcc) == "number" and prevOcc > 0) and prevOcc or 6
    entity.scaleInfo = {
      scale = 1, final2DScale = 1, contentW = 16, contentH = 16,
      offsetX = 0, offsetY = 0, imageW = 16, imageH = 96,
      renderedW = 16, renderedH = 16, originalW = 16, originalH = 96,
      logicalFootprintTiles = 1, grassOcclusionHeight = occ,
    }
    entity.grassOcclusionHeight = occ
    if entity.animation then
      entity.animation.source = "POKEPC_WALKERS"
    end
    if entity.entityPhase == "FALLBACK_LOADED" or entity.entityPhase == "CREATING" then
      entity.entityPhase = "REAL_ASSET_LOADED"
    end

    if not entity._followersExPokepcPose then
      local origPose = entity.pose
      function entity:pose()
        local spriteObj, px, py, facing, _, _, hop = origPose(self)
        return spriteObj, px, py, facing, walkPhaseOf(self), stepFlipOf(self), hop
      end
      entity._followersExPokepcPose = true
    end

    -- Refresh immersion flags so sheet swap does not leave a stale "above grass" state.
    pcall(function()
      local wilds = mod:find(WILDS_ID)
      local V = wilds and wilds.exports and wilds.exports.lib
      if not (V and type(V.require) == "function") then return end
      local ok, GrassOcclusion = pcall(V.require, "grass_occlusion")
      if not (ok and GrassOcclusion and GrassOcclusion.updateInGrassFlag) then return end
      local map = Game.overworld and Game.overworld.map
      GrassOcclusion.updateInGrassFlag(entity, wilds, map)
    end)
    return true
  end

  local function setWildsModOption(game, key, value)
    local g = game or Game
    if g and g.save then
      g.save.options = g.save.options or {}
      g.save.options.modOptions = g.save.options.modOptions or {}
      g.save.options.modOptions[WILDS_ID] =
        g.save.options.modOptions[WILDS_ID] or {}
      g.save.options.modOptions[WILDS_ID][key] = value
    end
    local mods = g and g.mods
    if mods then
      if mods.modOptions then
        mods.modOptions[WILDS_ID] = mods.modOptions[WILDS_ID] or {}
        mods.modOptions[WILDS_ID][key] = value
      end
      if mods.loader and mods.loader.modOptions then
        mods.loader.modOptions[WILDS_ID] = mods.loader.modOptions[WILDS_ID] or {}
        mods.loader.modOptions[WILDS_ID][key] = value
      end
    end
    if g and g.writeOptions then pcall(g.writeOptions, g) end
    if mods and mods.events and type(mods.events.emit) == "function" then
      pcall(mods.events.emit, mods.events, "mod.options_changed", {
        mod = WILDS_ID, key = key, value = value,
      })
    end
  end

  -- Dramatic Shape draws tall grass AFTER billboards. Raise visualY so grass
  -- only covers feet (was previously patched into Wilds spawn_render).
  local VOXEL_GRASS_LIFT = 8
  local function grassLiftOn()
    return optBool("wilds_grass_lift", false) == true
  end

  local function applyVoxelGrassLift(entity)
    if not entity or entity._followersExGrassLift then return end
    if type(entity.pose) ~= "function" then return end
    local prev = entity.pose
    function entity:pose()
      local spriteObj, px, py, facing, phase, flip, hop = prev(self)
      if grassLiftOn() and spriteObj and self.inGrassOverlay
         and type(py) == "number" then
        py = py - VOXEL_GRASS_LIFT
      end
      return spriteObj, px, py, facing, phase, flip, hop
    end
    entity._followersExGrassLift = true
  end

  -- Wilds 0.5.7+ / 0.6.0 ships native follow-sprites + EnhancedWorldSprite.
  local function wildsOwnsOwSprites(wilds)
    if not wilds then return false end
    local render = wilds.exports and wilds.exports.render
    if render and (type(render.attachEnhancedToEntity) == "function"
                   or type(render.syncEntityAnimation) == "function") then
      return true
    end
    local ver = tostring(wilds.version or (wilds.exports and wilds.exports.version) or "")
    local maj, min = ver:match("^(%d+)%.(%d+)")
    maj, min = tonumber(maj), tonumber(min)
    return maj ~= nil and min ~= nil and (maj > 0 or min >= 5)
  end

  local function applyGrassLiftToWilds(game)
    local wilds = mod:find(WILDS_ID)
    if not wilds then return end
    local mode = grassLiftOn() and "above" or "immersed"
    setWildsModOption(game, "pokemon_grass_render_mode", mode)
    local logic = wilds.exports and wilds.exports.logic
    if logic and type(logic.onOptionsChanged) == "function" then
      pcall(logic.onOptionsChanged, logic, {
        mod = WILDS_ID,
        key = "pokemon_grass_render_mode",
        value = mode,
      })
    end
    if not wildsOwnsOwSprites(wilds) then
      local ow = game and game.overworld
      for _, e in ipairs((ow and ow.entities) or {}) do
        if e and e.spawnId then pcall(applyVoxelGrassLift, e) end
      end
    end
  end

  local function refreshWildGrassLift(game)
    applyGrassLiftToWilds(game)
  end

  -- Compatibility stub: pack art is always PokePC walker sheets.
  local function getSpriteSet()
    return "pokepc"
  end

  local function installPokepcOwPipeline()
    if BillboardUvFix and type(BillboardUvFix.install) == "function" then
      local ok, detail = BillboardUvFix.install()
      if ok then
        mod.log:info("billboard UV fix: %s", tostring(detail))
      else
        mod.log:warn("billboard UV fix failed: %s", tostring(detail))
      end
    end

    local wilds = mod:find(WILDS_ID)
    if not (wilds and wilds.exports and wilds.exports.render) then
      return
    end

    -- Prefer PokePC walker sheets over Wilds enhanced (wrong card UV when off,
    -- and user asked for PokePC exclusively).
    setWildsModOption(Game, "use_animated_overworld_sprites", false)

    local root = followerRoot()
    local render = wilds.exports.render
    if root and render and not render._followersExPokepcMake then
      local origMake = render.makeEntity
      if type(origMake) == "function" then
        function render:makeEntity(game, record)
          local entity = origMake(self, game, record)
          if entity then
            pcall(applyPokepcWalkerSprite, entity, root)
            pcall(applyVoxelGrassLift, entity)
          end
          return entity
        end
        render._followersExPokepcMake = true
        mod.log:info("Wilds makeEntity → PokePC walker sheets (%s)", root)
      end
    end

    -- Retarget already-spawned wilds.
    if root then
      local logic = wilds.exports.logic
      local ents = logic and logic.entities
      if type(ents) == "table" then
        for _, e in pairs(ents) do
          if e and e.overworldWildSpawn then
            pcall(applyPokepcWalkerSprite, e, root)
            pcall(applyVoxelGrassLift, e)
          end
        end
      end
    end

    pcall(applyGrassLiftToWilds, Game)
  end

  mod.events:on("mods.loaded", installPokepcOwPipeline)
  mod.events:on("game.ready", installPokepcOwPipeline)
  mod.events:on("map.entered", function()
    local wilds = mod:find(WILDS_ID)
    local root = followerRoot()
    if not (wilds and root) then return end
    local logic = wilds.exports and wilds.exports.logic
    local ents = logic and logic.entities
    if type(ents) ~= "table" then return end
    for _, e in pairs(ents) do
      if e and e.overworldWildSpawn and not e.usingFollowerSprite then
        pcall(applyPokepcWalkerSprite, e, root)
        pcall(applyVoxelGrassLift, e)
      end
    end
  end)

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
          return tostring(liveFollowerCount(game))
        end,
        step = function(g)
          local n = liveFollowerCount(g) + 1
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
        label = "TOWN SPAWNS",
        value = function()
          return optBool("wilds_town_spawns", false) and "ON" or "OFF"
        end,
        step = function(g)
          local wilds = mod:find(WILDS_ID)
          local on = not optBool("wilds_town_spawns", false)
          setOpt("wilds_town_spawns", on, g)
          pcall(function()
            local logic = wilds and wilds.exports and wilds.exports.logic
            local ow = g and g.overworld
            if logic and ow and ow.map and type(logic.initializeForMap) == "function" then
              logic:initializeForMap(ow.map.id, g)
            end
          end)
        end,
      },
      {
        label = "GRASS LIFT",
        value = function()
          return optBool("wilds_grass_lift", false) and "ON" or "OFF"
        end,
        step = function(g)
          local on = not optBool("wilds_grass_lift", false)
          setOpt("wilds_grass_lift", on, g)
          pcall(refreshWildGrassLift, g)
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

  mod.exports.version = "1.0.19"
  mod.exports.liveFollowerCount = liveFollowerCount
  mod.exports.pokeReady = pokeReady
  mod.exports.ensureControlEngine = ensureControlEngine
  mod.exports.ensureWildsExtras = ensureWildsExtras
  mod.exports.getSpriteSet = getSpriteSet
  mod.log:info("FOLLOWERS_EX 1.0.19 — idle facing, ledge hop, grass occlude, always-reachable")
end

