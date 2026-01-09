local function dbg(...)
  if Config.Debug then
    print('^3[lf_emsplus]^7', ...)
  end
end

local function now()
  return os.time()
end

local function randBetween(a, b)
  return math.random(a, b)
end

local function vecDist(a, b)
  local dx = (a.x - b.x)
  local dy = (a.y - b.y)
  local dz = (a.z - b.z)
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ============================================================
-- Player helpers (qbx variations safe-guarded)
-- ============================================================
local function getPlayerData(src)
  local ok, player = pcall(function()
    return exports.qbx_core:GetPlayer(src)
  end)
  if ok and player then return player end

  -- fallback patterns (some builds expose differently)
  ok, player = pcall(function()
    return exports.qbx_core:GetPlayerByCitizenId(src)
  end)
  if ok and player then return player end

  return nil
end

local function getJobInfo(src)
  local pdata = getPlayerData(src)
  if not pdata then return nil end

  -- common qbx playerdata shapes
  local pd = pdata.PlayerData or pdata
  local job = pd.job or pd.Job or nil
  if not job then return nil end

  local name = job.name or job.label or job.id
  local onDuty = job.onduty
  if onDuty == nil then onDuty = true end

  return {
    name = name,
    onDuty = onDuty
  }
end

local function isEMS(src)
  if not Config.RequiredJob then return true end
  local j = getJobInfo(src)
  if not j then return false end
  if tostring(j.name) ~= tostring(Config.RequiredJob) then return false end
  return true
end

local function getOnlineEMS()
  local ems = {}
  for _, src in ipairs(GetPlayers()) do
    local s = tonumber(src)
    if s and isEMS(s) then
      table.insert(ems, s)
    end
  end
  return ems
end

local function getAnyEMSCoords()
  local ems = getOnlineEMS()
  if #ems == 0 then return nil end

  -- Use nearest-to-center random pick for variety
  local pick = ems[math.random(1, #ems)]
  local ped = GetPlayerPed(pick)
  if ped and ped ~= 0 then
    local c = GetEntityCoords(ped)
    return vec3(c.x, c.y, c.z)
  end
  return nil
end

-- ============================================================
-- Call state
-- ============================================================
local activeCall = nil
local lastCallAt = 0
local lastCallCoords = nil

local function newCallId()
  return tostring(now()) .. '-' .. tostring(math.random(1000, 9999))
end

local function pickComplaint()
  local list = Config.PatientComplaints or {}
  if #list == 0 then return "I need help..." end
  return list[math.random(1, #list)]
end

local function pickSeverity()
  -- Weighted: serious more common than critical
  -- tweak if you want more chaos
  local roll = math.random()
  if roll <= 0.25 then
    return 'critical'
  end
  return 'serious'
end

local function passesDistanceRules(candidate, emsCoords)
  if not candidate then return false end

  if emsCoords then
    local d = vecDist(candidate, emsCoords)
    if d < (Config.CallMinDistanceFromPlayer or 0.0) then
      return false
    end
    if d > (Config.CallMaxDistanceFromPlayer or 999999.0) then
      return false
    end
  end

  if lastCallCoords then
    local sep = vecDist(candidate, lastCallCoords)
    if sep < (Config.CallMinSeparationFromLast or 0.0) then
      return false
    end
  end

  return true
end

local function chooseCallCoords()
  local anchors = Config.CallAnchors or {}
  if #anchors == 0 then return nil end

  local emsCoords = getAnyEMSCoords()
  if Config.DisableCallsIfNoEMSOnline and not emsCoords then
    return nil
  end

  -- Try multiple anchors until one passes distance rules
  for _ = 1, 35 do
    local a = anchors[math.random(1, #anchors)]
    if passesDistanceRules(a, emsCoords) then
      return a
    end
  end

  -- If nothing matches strictly, relax (still avoid "feet apart" by lastCall rule)
  for _ = 1, 35 do
    local a = anchors[math.random(1, #anchors)]
    if lastCallCoords then
      local sep = vecDist(a, lastCallCoords)
      if sep >= (Config.CallMinSeparationFromLast or 0.0) then
        return a
      end
    else
      return a
    end
  end

  return nil
end

local function broadcastToEMS(eventName, payload)
  for _, src in ipairs(getOnlineEMS()) do
    TriggerClientEvent(eventName, src, payload)
  end
end

local function sendPhoneNotify(call)
  if not (Config.Phone and Config.Phone.enabled) then return end
  local ev = Config.Phone.notifyEvent
  if not ev then return end

  -- Bridge expects a structured payload (avoid undefined -> NPWD error)
  local payload = {
    app = "lexfall",
    title = "Lexfall EMS+",
    subtitle = call.complaint or "Medical emergency reported",
    callId = call.callId,
    severity = call.severity,
    coords = { x = call.coords.x, y = call.coords.y, z = call.coords.z }
  }

  broadcastToEMS(ev, payload)
end

local function sendPhoneCancel(callId, reason)
  if not (Config.Phone and Config.Phone.enabled) then return end
  local ev = Config.Phone.cancelEvent
  if not ev then return end
  broadcastToEMS(ev, { callId = callId, reason = reason or "cancelled" })
end

local function createCall()
  if activeCall then return end
  if (Config.MaxActiveCalls or 1) <= 0 then return end

  local t = now()
  if lastCallAt ~= 0 then
    local minGap = (Config.MinSecondsBetweenCalls or 180)
    if (t - lastCallAt) < minGap then
      return
    end
  end

  local coords = chooseCallCoords()
  if not coords then
    dbg("No valid coords found for new call.")
    return
  end

  activeCall = {
    callId = newCallId(),
    createdAt = t,
    expiresAt = t + (Config.AcceptTimeoutSec or 45),
    coords = coords,
    severity = pickSeverity(),
    complaint = pickComplaint(),
    acceptedBy = nil,
    stage = "pending"
  }

  lastCallAt = t
  lastCallCoords = coords

  dbg("Created call", activeCall.callId, activeCall.severity, coords.x, coords.y, coords.z)

  -- notify EMS clients (UI + waypoint/blip happens client-side)
  broadcastToEMS('lf_ems:client_newCall', activeCall)

  -- notify phone/dynamic-island
  sendPhoneNotify(activeCall)
end

local function expireCallIfNeeded()
  if not activeCall then return end
  if activeCall.stage ~= "pending" then return end

  if now() >= (activeCall.expiresAt or 0) then
    dbg("Call expired", activeCall.callId)
    sendPhoneCancel(activeCall.callId, "expired")
    broadcastToEMS('lf_ems:client_callExpired', { callId = activeCall.callId })
    activeCall = nil
  end
end

-- ============================================================
-- Public events
-- ============================================================
RegisterNetEvent('lf_ems:server_accept', function(callId)
  local src = source
  if not isEMS(src) then return end
  if not activeCall or activeCall.callId ~= callId then return end
  if activeCall.stage ~= "pending" then return end

  activeCall.acceptedBy = src
  activeCall.stage = "accepted"
  dbg("Call accepted", callId, "by", src)

  -- Tell everyone EMS-side (so other EMS can see it was taken)
  broadcastToEMS('lf_ems:client_callAccepted', { call = activeCall, by = src })

  -- Send only to accepter to force waypoint/blip creation if needed
  TriggerClientEvent('lf_ems:client_beginRoute', src, activeCall)
end)

RegisterNetEvent('lf_ems:server_deny', function(callId)
  local src = source
  if not isEMS(src) then return end
  if not activeCall or activeCall.callId ~= callId then return end
  if activeCall.stage ~= "pending" then return end

  dbg("Call denied", callId, "by", src)
  TriggerClientEvent('lf_ems:client_callDeniedAck', src, { callId = callId })
end)

-- called when patient outcome resolved (transport completed or death etc)
RegisterNetEvent('lf_ems:resolved', function(callId, outcome)
  local src = source
  if not callId then return end

  dbg("Resolved", callId, outcome or "unknown", "by", src)

  -- Fame hooks
  if Config.Fame and Config.Fame.enabled and Config.Fame.eventName then
    local pts = 0
    if Config.Fame.points and outcome then
      pts = Config.Fame.points[outcome] or 0
    end
    if pts ~= 0 then
      TriggerEvent(Config.Fame.eventName, src, pts, 'ems')
    end
  end

  -- Clear call if it matches
  if activeCall and activeCall.callId == callId then
    sendPhoneCancel(callId, "resolved")
    broadcastToEMS('lf_ems:client_callResolved', { callId = callId, outcome = outcome })
    activeCall = nil
  end
end)

-- Manual admin/test call (server console or in-game with perms)
RegisterCommand('lf_ems_testcall', function(src)
  if src ~= 0 then
    -- in-game: allow EMS only
    if not isEMS(src) then return end
  end
  if activeCall then
    if src ~= 0 then
      TriggerClientEvent('ox_lib:notify', src, { title="Lexfall EMS+", description="A call is already active.", type="error" })
    end
    return
  end
  lastCallAt = 0 -- allow immediate
  createCall()
end, false)

-- ============================================================
-- Scheduler loop
-- ============================================================
CreateThread(function()
  math.randomseed(GetGameTimer() + os.time())

  -- initial delay so server boots clean
  Wait(15000)

  while true do
    expireCallIfNeeded()

    local emsOnline = getOnlineEMS()
    if not Config.DisableCallsIfNoEMSOnline or #emsOnline > 0 then
      if not activeCall then
        -- Random gap between calls
        local waitSeconds = randBetween(Config.MinSecondsBetweenCalls or 180, Config.MaxSecondsBetweenCalls or 360)
        dbg("Waiting", waitSeconds, "seconds until next call window")
        for _ = 1, waitSeconds do
          expireCallIfNeeded()
          Wait(1000)
          if activeCall then break end
        end
        if not activeCall then
          createCall()
        end
      end
    end

    Wait(2000)
  end
end)
