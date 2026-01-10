local spawnedPatients = {}
local activeBlip = nil
local activeZone = nil

local function notify(title, msg, type)
  exports.ox_lib:notify({
    title = title,
    description = msg,
    type = type or 'inform'
  })
end

local function clearBlips()
  if activeBlip then
    RemoveBlip(activeBlip)
    activeBlip = nil
  end
end

local function buildBlip(call)
  local coords = safeGround(call.coords)

  activeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(activeBlip, 153)
  SetBlipColour(activeBlip, call.severity == 'critical' and 1 or 5)
  SetBlipScale(activeBlip, 0.9)
  SetBlipAsShortRange(activeBlip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('EMS Call')
  EndTextCommandSetBlipName(activeBlip)
end

local function getLocalServerId()
  return GetPlayerServerId(PlayerId())
end

local function cleanupCall(callId)
  local st = spawnedPatients[callId]
  if not st then return end

  if st.ped and DoesEntityExist(st.ped) then
    DeleteEntity(st.ped)
  end

  spawnedPatients[callId] = nil
  clearBlips()

  if activeZone then
    exports.ox_target:removeZone(activeZone)
    activeZone = nil
  end
end

local function pickHospital()
  local hospitals = Config.Hospitals or {}
  if #hospitals == 0 then return nil end

  local ped = PlayerPedId()
  local pcoords = GetEntityCoords(ped)
  local closest = hospitals[1]
  local bestDist = #(pcoords - closest.coords)

  for i = 2, #hospitals do
    local h = hospitals[i]
    local dist = #(pcoords - h.coords)
    if dist < bestDist then
      bestDist = dist
      closest = h
    end
  end

  return closest
end

local function playTreatAnim()
  if Config.Anim and Config.Anim.enabled then
    RequestAnimDict(Config.Anim.dict)
    while not HasAnimDictLoaded(Config.Anim.dict) do Wait(0) end
    TaskPlayAnim(
      PlayerPedId(),
      Config.Anim.dict,
      Config.Anim.name,
      8.0,
      -8.0,
      Config.TreatDurationMs or 7000,
      Config.Anim.flag or 49,
      0.0,
      false,
      false,
      false
    )
  else
    TaskStartScenarioInPlace(PlayerPedId(), 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
  end
end

local function safeGround(coords)
  local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, false)
  if found then
    return vec3(coords.x, coords.y, z)
  end
  return coords
end

-- ============================================================
-- CALL RECEIVED
-- ============================================================
RegisterNetEvent('lf_ems:client_newCall', function(call)
  if spawnedPatients[call.callId] then return end

  notify('Lexfall EMS+', call.complaint or 'Medical emergency reported', 'info')

  spawnedPatients[call.callId] = {
    call = call,
    stage = 'enroute',
    ped = nil
  }

  if not Config.BlipOnAccept then
    buildBlip(call)
  end

  if not Config.WaypointOnAccept then
    SetNewWaypoint(call.coords.x, call.coords.y)
  end
end)

-- ============================================================
-- CALL ACCEPTED
-- ============================================================
RegisterNetEvent('lf_ems:client_beginRoute', function(call)
  if not spawnedPatients[call.callId] then return end

  if Config.BlipOnAccept then
    clearBlips()
    buildBlip(call)
  end

  if Config.WaypointOnAccept then
    SetNewWaypoint(call.coords.x, call.coords.y)
  end
end)

-- ============================================================
-- SPAWN PATIENT
-- ============================================================
local function spawnPatient(callId)
  local st = spawnedPatients[callId]
  if not st or st.ped then return end

  local model = joaat('a_m_m_business_01')
  RequestModel(model)
  while not HasModelLoaded(model) do Wait(0) end

  local coords = safeGround(st.call.coords)

  local ped = CreatePed(4, model, coords.x, coords.y, coords.z, 0.0, false, true)
  SetEntityAsMissionEntity(ped, true, true)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SUNBATHE_BACK', 0, true)

  st.ped = ped
  st.stage = 'on_scene'

  exports.ox_target:addLocalEntity(ped, {
    {
      label = 'Treat patient',
      icon = 'fa-solid fa-kit-medical',
      distance = 2.5,
      onSelect = function()
        TriggerEvent('lf_ems:client_treat', callId)
      end
    }
  })
end

-- ============================================================
-- PLAYER ARRIVES NEAR SCENE
-- ============================================================
CreateThread(function()
  while true do
    for callId, st in pairs(spawnedPatients) do
      if st.stage == 'enroute' then
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        if #(pcoords - st.call.coords) < 40.0 then
          spawnPatient(callId)
        end
      end
    end
    Wait(1500)
  end
end)

-- ============================================================
-- TREATMENT
-- ============================================================
RegisterNetEvent('lf_ems:client_treat', function(callId)
  local st = spawnedPatients[callId]
  if not st or not st.ped then return end
  if st.stage ~= 'on_scene' then return end

  st.stage = 'treating'

  ClearPedTasksImmediately(PlayerPedId())
  playTreatAnim()

  local ok = exports.ox_lib:progressCircle({
    duration = Config.TreatDurationMs or 7000,
    label = 'Treating patient...',
    position = 'bottom',
    canCancel = false,
    disable = { move=true, car=true, combat=true }
  })

  ClearPedTasks(PlayerPedId())

  if not ok then
    st.stage = 'on_scene'
    return
  end

  st.stage = 'stabilized'
  if not Config.TransportEnabled then
    local outcome = st.call.severity == 'critical' and 'saved_critical' or 'saved_serious'
    notify('Lexfall EMS+', 'Patient stabilized on scene.', 'success')
    TriggerServerEvent('lf_ems:resolved', callId, outcome)
    cleanupCall(callId)
    return
  end

  notify('Lexfall EMS+', 'Patient stabilized. Transport to hospital.', 'success')

  exports.ox_target:addLocalEntity(st.ped, {
    {
      label = 'Load into ambulance',
      icon = 'fa-solid fa-truck-medical',
      distance = 2.5,
      onSelect = function()
        TriggerEvent('lf_ems:client_loaded', callId)
      end
    }
  })
end)

-- ============================================================
-- LOADED INTO AMBULANCE
-- ============================================================
RegisterNetEvent('lf_ems:client_loaded', function(callId)
  local st = spawnedPatients[callId]
  if not st or not st.ped then return end

  DeleteEntity(st.ped)
  st.ped = nil
  st.stage = 'loaded'

  clearBlips()

  local hospital = pickHospital()
  if not hospital then
    notify('Lexfall EMS+', 'No hospital configured for dropoff.', 'error')
    return
  end

  st.hospital = hospital
  SetNewWaypoint(hospital.coords.x, hospital.coords.y)

  notify('Lexfall EMS+', ('Transport patient to %s.'):format(hospital.name or 'hospital'), 'info')

  activeZone = exports.ox_target:addSphereZone({
    coords = hospital.coords,
    radius = hospital.radius or 5.0,
    debug = false,
    options = {
      {
        label = 'Drop off patient',
        icon = 'fa-solid fa-hospital',
        onSelect = function()
          TriggerEvent('lf_ems:client_dropoff', callId)
        end
      }
    }
  })
end)

-- ============================================================
-- DROPOFF
-- ============================================================
RegisterNetEvent('lf_ems:client_dropoff', function(callId)
  local st = spawnedPatients[callId]
  if not st or st.stage ~= 'loaded' then return end

  exports.ox_lib:progressCircle({
    duration = Config.DropoffDurationMs or 4200,
    label = 'Handing off to hospital staff...',
    position = 'bottom',
    disable = { move=true, car=true, combat=true }
  })

  local outcome = st.call.severity == 'critical' and 'saved_critical' or 'saved_serious'
  TriggerServerEvent('lf_ems:resolved', callId, outcome)

  notify('Lexfall EMS+', 'Patient delivered successfully.', 'success')
  cleanupCall(callId)
end)

-- ============================================================
-- CALL STATUS UPDATES
-- ============================================================
RegisterNetEvent('lf_ems:client_callAccepted', function(data)
  if not data or not data.call then return end
  local callId = data.call.callId
  if not callId or not spawnedPatients[callId] then return end

  if data.by and data.by ~= getLocalServerId() then
    notify('Lexfall EMS+', 'Call accepted by another unit.', 'info')
    cleanupCall(callId)
  end
end)

RegisterNetEvent('lf_ems:client_callDeniedAck', function()
  notify('Lexfall EMS+', 'Call denied.', 'info')
end)

RegisterNetEvent('lf_ems:client_callExpired', function(data)
  if not data or not data.callId then return end
  notify('Lexfall EMS+', 'Call expired.', 'info')
  cleanupCall(data.callId)
end)

RegisterNetEvent('lf_ems:client_callResolved', function(data)
  if not data or not data.callId then return end
  notify('Lexfall EMS+', 'Call resolved.', 'info')
  cleanupCall(data.callId)
end)
