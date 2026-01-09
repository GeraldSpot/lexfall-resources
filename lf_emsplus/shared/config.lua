Config = Config or {}

-- ============================================================
-- Core
-- ============================================================
Config.Debug = false

-- Job lock (you confirmed qbx ambulance job is "ambulance")
Config.RequiredJob = 'ambulance'  -- set false/nil to disable job lock

-- How often calls can be generated (global per-server)
Config.MinSecondsBetweenCalls = 180         -- 3 minutes minimum spacing
Config.MaxSecondsBetweenCalls = 360         -- up to 6 minutes (randomized)
Config.MaxActiveCalls = 1                   -- keep it immersive, one at a time
Config.DisableCallsIfNoEMSOnline = false    -- set true if you only want calls when EMS is on duty

-- Distance rules: this fixes "calls feet apart"
Config.CallMinDistanceFromPlayer = 1200.0   -- must drive: at least ~1.2km away
Config.CallMaxDistanceFromPlayer = 5200.0   -- prevents sending you across the whole map
Config.CallMinSeparationFromLast = 900.0    -- next call can't be close to last location

-- When player accepts
Config.AcceptTimeoutSec = 45                -- how long call sits before auto-expire if not accepted
Config.WaypointOnAccept = true
Config.BlipOnAccept = true

-- ============================================================
-- Patient + Treatment
-- ============================================================
-- Treatment time (progress circle)
Config.TreatDurationMs = 7000

-- Transport handoff time
Config.DropoffDurationMs = 4200

-- Simple “premium-feel” patient dialogue snippets
Config.PatientComplaints = {
  "I can’t breathe right... my chest feels tight.",
  "My head is pounding... I think I’m gonna pass out.",
  "I slipped and everything went black for a second.",
  "My stomach is twisting up… I feel terrible.",
  "I got hit… I can’t feel my hand right.",
  "Please… it hurts to move."
}

-- Treatment options menu (minimal UI; no stretcher required)
Config.TreatmentOptions = {
  { id = 'bandage',  label = 'Bandage / Wrap',       success = "Bleeding controlled.",  fail = "Bandage didn’t hold." },
  { id = 'oxygen',   label = 'Oxygen / Airway',      success = "Breathing improved.",   fail = "Airway still compromised." },
  { id = 'iv',       label = 'Start IV Fluids',      success = "Vitals stabilizing.",   fail = "Vein collapsed." },
  { id = 'pain',     label = 'Pain Management',      success = "Pain reduced.",         fail = "Pain persists." },
  { id = 'cpr',      label = 'CPR / Resuscitation',  success = "Pulse regained!",       fail = "No response…" }
}

-- Success chances by severity (tweak as you want)
Config.Severity = {
  serious  = { treatSuccess = 0.78 },
  critical = { treatSuccess = 0.55 }
}

-- ============================================================
-- Animations (treating feels like a real job)
-- ============================================================
Config.Anim = {
  enabled = true,
  dict = 'amb@medic@standing@tendtodead@base',
  name = 'base',
  flag = 49
}

-- ============================================================
-- Transport / Hospital dropoff
-- ============================================================
Config.TransportEnabled = true
Config.StretcherEnabled = false -- you said: implement everything BUT stretcher for serious cases (we can enable later)

-- Hospital dropoff points (add more later if you want)
Config.Hospitals = {
  {
    name = 'Pillbox',
    coords = vec3(307.74, -1433.43, 29.97),
    radius = 6.0
  }
}

-- ============================================================
-- Fame hooks (optional)
-- ============================================================
Config.Fame = {
  enabled = true,
  eventName = 'lf_fame:add', -- your fame resource should listen for this server event; adjust if needed
  points = {
    saved_serious = 2,
    saved_critical = 4,
    death = -2
  }
}

-- ============================================================
-- NPWD / Phone integration hooks (bridge handles UI)
-- ============================================================
Config.Phone = {
  enabled = true,
  -- we send events; your lf_npwd_bridge listens and shows dynamic-island + accept/deny
  notifyEvent = 'lf_npwd_bridge:ems:notify',
  cancelEvent = 'lf_npwd_bridge:ems:cancel'
}

-- ============================================================
-- Call spawn zones (roads + sidewalks around LS)
-- You can add/remove points. These are "candidate anchors";
-- we search near them and apply ground + distance rules.
-- ============================================================
Config.CallAnchors = {
  vec3(215.76, -810.12, 30.73),   -- Legion area
  vec3(-303.21, -990.64, 31.08),  -- Strawberry
  vec3(1150.94, -1527.30, 34.84), -- El Burro
  vec3(361.22, -1659.45, 26.72),  -- Davis
  vec3(-1204.58, -1176.25, 7.69), -- Vespucci
  vec3(-558.24, -210.92, 38.21),  -- Rockford
  vec3(826.44, -1032.22, 26.29),  -- La Mesa
  vec3(-42.40, -1747.18, 29.32),  -- Grove-ish
  vec3(1691.84, 3573.12, 35.62),  -- Sandy edge
  vec3(2567.14, 425.02, 108.46)   -- East LS
}
