-- Dramatic Shape SpriteBillboards builds UVs from Assets.image(def.image)
-- assuming a 16-tall strip slice even when frames==1. Large OW sheets
-- (battle fronts, generated sprites) then show only their top-left 16×16
-- — i.e. a zoomed mess on every wild. Walker strips (frames>1) keep the
-- usual 16×16 frame slices.
return function(mod)
  local Assets = require("src.render.Assets")

  local function install()
    local ds = mod:find("DRAMATIC_SHAPE")
    local lib = ds and ds.exports and ds.exports.lib
    if not (lib and type(lib.require) == "function") then
      return false, "DRAMATIC_SHAPE lib missing"
    end
    local okSB, SB = pcall(lib.require, "SpriteBillboards")
    local okV3, Voxel3D = pcall(lib.require, "Voxel3D")
    if not (okSB and SB and okV3 and Voxel3D) then
      return false, "SpriteBillboards/Voxel3D unavailable"
    end
    if SB._followersExUvFix then return true, "already" end

    local meshCache = {}

    local function buildCard(def, frame)
      if not (def and type(def.image) == "string") then return nil end
      local ok, img = pcall(Assets.image, def.image)
      if not (ok and img) then return nil end
      local iw, ih = img:getDimensions()
      if not (iw and ih and iw > 0 and ih > 0) then return nil end

      local u0, u1, v0, v1
      local frames = math.max(1, tonumber(def.frames) or 1)
      -- Gen 1 OW sheets are 16-wide vertical strips (nurse 16×48, walkers
      -- 16×96, …). Those must keep 16×16 frame slices. The old gate only
      -- treated def.walker strips as sliced, so static NPCs (Joy, etc.)
      -- got the WHOLE sheet squashed onto the card — horizontal bands in
      -- 1ST/3RD. Whole-image mapping stays for large single frames
      -- (Wilds battle-front OW, generated sheets).
      local owStrip = iw <= 16 and ih >= 32
      local sliceFrames = frames > 1 or owStrip or def.walker
      if sliceFrames then
        local fy = (tonumber(frame) or 0) * 16
        if fy + 16 > ih then fy = 0 end
        local fw = math.min(16, iw)
        u0, u1 = 0.02 / iw, (fw - 0.02) / iw
        v0, v1 = (fy + 0.05) / ih, (fy + 15.95) / ih
      else
        -- Whole image on the 16×16 card (fixes zoomed top-left crop).
        u0, u1 = 0.02 / iw, (iw - 0.02) / iw
        v0, v1 = 0.05 / ih, (ih - 0.05) / ih
      end

      local verts = {
        { 0, 0, 0, u0, v1, 1 }, { 16, 0, 0, u1, v1, 1 },
        { 16, 16, 0, u1, v0, 1 }, { 0, 16, 0, u0, v0, 1 },
      }
      local indices = {}
      Voxel3D.pushQuad(indices, 0)
      return Voxel3D.newMesh(verts, indices)
    end

    function SB.mesh(def, frame)
      if not def or type(def.image) ~= "string" then return nil end
      local key = def.image .. "#" .. tostring(frame or 0)
        .. "#exuv4#" .. tostring(def.frames or 1)
        .. (def.walker and "W" or "S")
      if meshCache[key] == nil then
        local ok, m = pcall(buildCard, def, frame)
        meshCache[key] = (ok and m) or false
      end
      return meshCache[key] or nil
    end
    SB.shadowQuad = SB.mesh

    local origInv = SB.invalidate
    function SB.invalidate()
      meshCache = {}
      if type(origInv) == "function" then pcall(origInv) end
    end

    SB._followersExUvFix = true
    return true, "installed"
  end

  return { install = install }
end
