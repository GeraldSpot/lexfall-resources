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

  local coords = safeGround(call.coords)

  activeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(activeBlip, 153)
  SetBlipColour(activeBlip, call.severity == 'critical' and 1 or 5)
  SetBlipScale(activeBlip, 0.9)
  SetBlipAsShortRange(activeBlip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('EMS Call')
  EndTextCommandSetBlipName(activeBlip)

  SetNewWaypoint(coords.x, coords.y)

  spawnedPatients[call.callId] = {
    call = call,
    stage = 'enroute',
    ped = nil
  }
end)

-- ============================================================
-- CALL ACCEPTED
-- ============================================================
RegisterNetEvent('lf_ems:client_beginRoute', function(call)
  if not spawnedPatients[call.callId] then return end
  SetNewWaypoint(call.coords.x, call.coords.y)
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
  TaskStartScenarioInPlace(PlayerPedId(), 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)

  local ok = exports.ox_lib:progressCircle({
    duration = 6000,
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

  local hospital = vec3(311.2, -592.7, 43.3) -- Pillbox
  SetNewWaypoint(hospital.x, hospital.y)

  notify('Lexfall EMS+', 'Transport patient to Pillbox.', 'info')

  activeZone = exports.ox_target:addSphereZone({
    coords = hospital,
    radius = 5.0,
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
    duration = 4000,
    label = 'Handing off to hospital staff...',
    position = 'bottom',
    disable = { move=true, car=true, combat=true }
  })

  TriggerServerEvent('lf_ems:resolved', callId, 'saved_serious')

  notify('Lexfall EMS+', 'Patient delivered successfully.', 'success')

  if activeZone then
    exports.ox_target:removeZone(activeZone)
    activeZone = nil
  end

  spawnedPatients[callId] = nil
end)
