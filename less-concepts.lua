-- less concepts:
-- cellular automata sequencer
-- v3.1.2 230516 by @vicimity (linus schrab)
-- + @dan_derks (dan derks)
-- llllllll.co/t/less-concepts-3/
--
-- hold key 1: switch between
-- less concepts +
-- ~ r e f r a i n
--
-- enc 1: navigate
-- enc 2: change left side //
-- enc 3: // change right side
--
-- key 3: randomize selected
-- key 2: take snapshot
-- when snapshots selected...
-- key 2: recall snapshot
-- hold key 2 then key 3 (NEW):
-- delete selected snapshot
-- params: midi, +/- st, timbre,
-- probabilities, delay settings,
-- save ALL to set
--
-- plug in grid
-- (1,1) to (8,2): bits
-- (1, 9) and (2, 9) : mute bits
-- (10,1) to (16,2): octaves
-- (1,3) to (16,3): randomize
-- (2,5) + (1,4) to (16,5): low
-- (1,5) + (1,4) to (16,5): high
-- (16,6): take snapshot
-- (15,6): clear selected (hold)
-- (14,6): clear all snapshots (hold)
-- (9,7) to (16,8): snapshots
-- (1,6) to (3,6): time +/-
--
-- seek.
-- think.
-- discover.

local midigrid_size = 64

engine.name = "Passersby"
passersby = include "passersby/lib/passersby_engine"

refrain = include "lib/refrain"
MusicUtil = require "musicutil"

seed = 0
rule = 0
next_seed = nil
new_low = 1
new_high = 14
coll = 1
new_seed = seed
new_rule = rule
local screen_focus = 1
selected_preset = 0
local KEY2 = false
local KEY3 = false
local voice = {}
for i = 1,2 do
  voice[i] = {}
  voice[i].bit = 0
  voice[i].octave = 0
  voice[i].active_notes = {}
  voice[i].ch = 1
end
local semi = 0
preset_count = 0
names = {}
notes = {}
for i = 1, #MusicUtil.SCALES do
  table.insert(names, string.lower(MusicUtil.SCALES[i].name))
  table.insert(notes, MusicUtil.generate_scale(0, names[i], 7))
end
table.insert(names,"olafur")
active_olafur_notes = 0

edit_foci = {
  "lc_bits",
  "seed/rule",
  "octaves",
  "low/high",
  "clock",
  "lc_gate_probs",
  "rand_prob",
  "presets",
  "cycle"
}
local edit = "seed/rule"
local dd = 2
random_gate = {}
for i = 1,4 do
  random_gate[i] = {}
  random_gate[i].comparator = 99
  random_gate[i].probability = 100
end
random_note = {}
for i = 1,2 do
  random_note[i] = {}
  random_note[i].tran = 0
  random_note[i].down = 0
  random_note[i].comparator = 99
  random_note[i].probability = 100
  random_note[i].add = 0
end
new_preset_pool = {}
for i = 1,17 do
  new_preset_pool[i] = {}
  new_preset_pool[i].seed = {}
  new_preset_pool[i].rule = {}
  new_preset_pool[i].v1_bit = {}
  new_preset_pool[i].v2_bit = {}
  new_preset_pool[i].new_low = {}
  new_preset_pool[i].new_high = {}
  new_preset_pool[i].v1_octave = {}
  new_preset_pool[i].v2_octave = {}
  new_preset_pool[i].sel_ppqn_div = {}
  new_preset_pool[i].p_duration = {}
end
local crow_gate_length = 0.005 --5 ms for 'standard' trig behavior
local crow_gate_volts = 5
local ppqn = 96
local pset_wsyn_curve = 0
local pset_wsyn_ramp = 0
local pset_wsyn_fm_index = 0
local pset_wsyn_fm_env = 0
local pset_wsyn_fm_ratio_num = 0
local pset_wsyn_fm_ratio_den = 0
local pset_wsyn_lpg_time = 0
local pset_wsyn_lpg_symmetry = 0
local pset_wsyn_vel = 0
-- please keep ppqn_divisions and ppqn_names same length and odd numbered lengths
-- thank you @Zifor for clearing out the meaning of t
local ppqn_divisions_variants = {
  {2/1, 3/1, 4/1, 6/1, 8/1},
  {1/4, 1/3, 1/2, 1/1.5, 1/1, 1.5/1, 2/1, 3/1, 4/1},
  {1/8, 1/6, 1/4, 1/3, 1/2, 1/1.5, 1/1, 1.5/1, 2/1,  3/1, 4/1, 6/1, 8/1}
}
local ppqn_names_variants = {
  {'1/8', '1/8t', '1/16', '1/16t', '1/32'}, --centroid 1/16
  {'1/1', '1/1t', '1/2', '1/2t', '1/4', '1/4t', '1/8', '1/8t', '1/16'}, --centroid 1/4
  {'2/1', '2/1t', '1/1', '1/1t', '1/2', '1/2t', '1/4', '1/4t', '1/8', '1/8t', '1/16', '1/16t', '1/32'} --centroid 1/4
}
local ppqn_divisions = ppqn_divisions_variants[1]
local ppqn_names = ppqn_names_variants[1]
ppqn_counter = 1
sel_ppqn_div = util.round((1+#ppqn_divisions)/2)
local selected_time_param = 1

time_clamp_min = 1
time_clamp_max = #ppqn_divisions

local cycle_modes = {"*", "-", "<", "~", ">", "<*", "~*", ">*"} -- destructive, off, down, random, up
local cycle_sel = "-"
local p_duration = 4
local p_duration_counter = 1
local gridnote = 0
local screennote = nil
local gridplay_active = false
local ignorenote = nil
local display_voice = {false, false}

local options = {}

local destructive = false
local preset_key_is_held = false
local transport_run = true

local grid_dirty = false
local screen_dirty = false

function r()
  norns.script.load(norns.state.script)
end

function clock.transport.start()
  if params:get("midi_transport") == 2 then
    p_duration_counter = 1
    selected_preset = preset_count > 0 and 1 or 0
    ppqn_counter = 1
    transport_run = true
  end
end

function clock.transport.stop()
  if params:get("midi_transport") == 2 then
    for i=1,2 do
      notes_off(i)
    end
    transport_run = false
    next_seed = new_seed
  end
end


-- this section is all maths + computational events

-- maths: translate the seed integer to binary
local function seed_to_binary()
  seed_as_binary = {}
  for i = 0,7 do
    table.insert(seed_as_binary, (seed & (2 ^ i)) >> i)
  end
end

-- maths: translate the rule integer to binary
local function rule_to_binary()
  rule_as_binary = {}
  for i = 0,7 do
    table.insert(rule_as_binary, (rule & (2 ^ i)) >> i)
  end
end

-- maths: basic compare function, used in bang()
local function compare (s, n)
  if type(s) == type(n) then
        if type(s) == "table" then
                  for loop=1, 3 do
                    if compare (s[loop], n[loop]) == false then
                        return false
                    end
                  end

                return true
        else
            return s == n
        end
    end
    return false
end

-- maths: scale seeds to the note pool + range selected
local function scale(lo, hi, received)
  scaled = math.floor(((((received) / (256)) * (hi + 1 - lo) + lo))) 
  pass_to_refrain = received
end

-- pack the seeds into clusters, compare these against neighborhoods to determine gates in iterate()
local function bang()
  --redraw()
  screen_dirty = true
  seed_to_binary()
  rule_to_binary()
  seed_pack1 = {seed_as_binary[1], seed_as_binary[8], seed_as_binary[7]}
  seed_pack2 = {seed_as_binary[8], seed_as_binary[7], seed_as_binary[6]}
  seed_pack3 = {seed_as_binary[7], seed_as_binary[6], seed_as_binary[5]}
  seed_pack4 = {seed_as_binary[6], seed_as_binary[5], seed_as_binary[4]}
  seed_pack5 = {seed_as_binary[5], seed_as_binary[4], seed_as_binary[3]}
  seed_pack6 = {seed_as_binary[4], seed_as_binary[3], seed_as_binary[2]}
  seed_pack7 = {seed_as_binary[3], seed_as_binary[2], seed_as_binary[1]}
  seed_pack8 = {seed_as_binary[2], seed_as_binary[1], seed_as_binary[8]}
  
  neighborhoods1 = {1,1,1}
  neighborhoods2 = {1,1,0}
  neighborhoods3 = {1,0,1}
  neighborhoods4 = {1,0,0}
  neighborhoods5 = {0,1,1}
  neighborhoods6 = {0,1,0}
  neighborhoods7 = {0,0,1}
  neighborhoods8 = {0,0,0}
  
  local function com (seed_packN, lshift, mask)
    if compare (seed_packN,neighborhoods1) then
      return (rule_as_binary[8] << lshift) & mask
    elseif compare (seed_packN, neighborhoods2) then
      return (rule_as_binary[7] << lshift) & mask
    elseif compare (seed_packN, neighborhoods3) then
      return (rule_as_binary[6] << lshift) & mask
    elseif compare (seed_packN, neighborhoods4) then
      return (rule_as_binary[5] << lshift) & mask
    elseif compare (seed_packN, neighborhoods5) then
      return (rule_as_binary[4] << lshift) & mask
    elseif compare (seed_packN, neighborhoods6) then
      return (rule_as_binary[3] << lshift) & mask
    elseif compare (seed_packN, neighborhoods7) then
      return (rule_as_binary[2] << lshift) & mask
    elseif compare (seed_packN, neighborhoods8) then
      return (rule_as_binary[1] << lshift) & mask
    else return (0 << lshift) & mask
    end
  end
  
  out1 = com(seed_pack1, 7, 128)
  out2 = com(seed_pack2, 6, 64)
  out3 = com(seed_pack3, 5, 32)
  out4 = com(seed_pack4, 4, 16)
  out5 = com(seed_pack5, 3, 8)
  out6 = com(seed_pack6, 2, 4)
  out7 = com(seed_pack7, 1, 2)
  out8 = com(seed_pack8, 0, 1)
  
  next_seed = out1+out2+out3+out4+out5+out6+out7+out8
end

function notes_off(n)
  for i=1,#voice[n].active_notes do
    if params:get("voice_"..n.."_midi_A") == 2 and
    params:string("scale") ~= "olafur" or (params:string("scale") == "olafur" and (params:get("olafur_device") ~= params:get("midi_device"))) then
      m:note_off(voice[n].active_notes[i],0,params:get("midi_A"))
    end
    if params:get("voice_"..n.."_midi_B") == 2 and
    params:string("scale") ~= "olafur" or (params:string("scale") == "olafur" and (params:get("olafur_device") ~= params:get("midi_device"))) then
      m:note_off(voice[n].active_notes[i],0,params:get("midi_B"))
    end
    -- engine.noteOff(n)
    voice[n].active_notes = {}
  end
end

function force_notes_off()
  for n = 1,2 do
    for i=1,#voice[n].active_notes do
      m:note_off(voice[n].active_notes[i],0,params:get("midi_A"))
      m:note_off(voice[n].active_notes[i],0,params:get("midi_B"))
      voice[n].active_notes = {}
    end
  end
end

-- if user-defined bit in the binary version of a seed equals 1, then note event [aka, bit-wise gating]

local function iterate()
  if transport_run then
    if preset_count == 0 then 
      p_duration = params:get("p_duration")
      if edit == "cycle" then edit = "seed/rule" end
    end
    if cycle_sel ~= "*" and cycle_sel ~= "-" then
      p_duration_counter = p_duration_counter + 1
    end
    if ppqn_counter > ppqn / ppqn_divisions[sel_ppqn_div] then
      ppqn_counter = 1

      if string.find(cycle_sel, "*") then
        destructive = true
      else
        destructive = false
      end

      if destructive then
        new_preset_pack(selected_preset)
      end
      if preset_key_is_held then
      elseif p_duration_counter > ppqn*p_duration and preset_key_is_held == false then
        p_duration_counter = 1
        if (cycle_sel ~= "-" and cycle_sel ~= "*") and preset_count > 0 then --cycle if there are presets and cycle mode is "on"
          if string.find(cycle_sel, ">") then --cycle up
            selected_preset = selected_preset + 1
            if selected_preset > preset_count then
              selected_preset = 1
            end
          elseif string.find(cycle_sel, "<") then --cycle down
              selected_preset = selected_preset - 1
            if selected_preset <= 0 then
              selected_preset = preset_count
            end
          elseif string.find(cycle_sel, "~") then --'cycle' random
            selected_preset = math.random(1, preset_count)
          end
          new_preset_unpack(selected_preset)
        end
      end

      for y=4,5 do
        for x=1,16 do
          if momentary[x][y] then
            if x > 16 then
              ignorenote = 16 + x
            else
              ignorenote = x
            end
          end
        end
      end

      for i = 1,2 do notes_off(i) end
      seed = next_seed
      bang()
      screennote = nil
      gridnote = nil
      for i = 1,2 do
        display_voice[i] = false
        if seed_as_binary[voice[i].bit] == 1 and tab.count(notes[coll]) ~= 0 then
          random_gate[i].comparator = math.random(0,100)
          if random_gate[i].comparator < random_gate[i].probability then
            scale(new_low,new_high,seed)
            random_note[i].comparator = math.random(0,100)
            display_voice[i] = true
            if random_note[i].comparator < random_note[i].probability then
              random_note[i].add = random_note[i].tran
            else
              random_note[i].add = 0
            end
            screennote = notes[coll][scaled] + random_note[i].add
            gridnote = scaled
              if params:get("voice_"..i.."_engine") == 2 then
                engine.noteOn(i,midi_to_hz((notes[coll][scaled])+(48+(voice[i].octave * 12)+semi+random_note[i].add)),100)
              end
              if params:get("voice_"..i.."_midi_A") == 2 and
              params:string("scale") ~= "olafur" or (params:string("scale") == "olafur" and (params:get("olafur_device") ~= params:get("midi_device"))) then
                m:note_on((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add),100,params:get("midi_A"))
              end
              if params:get("voice_"..i.."_midi_B") == 2 and
              params:string("scale") ~= "olafur" or (params:string("scale") == "olafur" and (params:get("olafur_device") ~= params:get("midi_device"))) then
                m:note_on((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add),100,params:get("midi_B"))
              end
              if params:get("voice_"..i.."_crow_1") == 2 then
                crow.output[1].volts = (((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add)-48)/12)
                crow.output[2]()
              end
              if params:get("voice_"..i.."_crow_2") == 2 then
                crow.output[3].volts = (((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add)-48)/12)
                crow.output[4]()
              end
              if params:get("voice_"..i.."_JF") == 2 then
                crow.ii.jf.play_note(((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add)-48)/12,5)
              end
              if params:get("voice_"..i.."_w") == 2 then
                crow.send("ii.wsyn.play_note(".. ((notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[1].add)-48)/12 ..", " .. pset_wsyn_vel .. ")")
              end
            --end
          table.insert(voice[i].active_notes,(notes[coll][scaled])+(36+(voice[i].octave*12)+semi+random_note[i].add))
          end
      end

      -- EVENTS FOR R E F R A I N
      if seed_as_binary[track[i].bit] == 1 then
        random_gate[i+2].comparator = math.random(0,100)
        if random_gate[i+2].comparator < random_gate[i+2].probability then
          refrain.reset(i,pass_to_refrain)
        end
      end
    end
    --redraw()
    screen_dirty = true
    grid_dirty = true
    end
  end
end

function change(s)
  if s == 1 then
    iterate()
  end
end

-- convert midi note to hz for Passersby engine
function midi_to_hz(note)
  return (440 / 32) * (2 ^ ((note - 9) / 12))
end

-- allow user to define the transposition of voice 1 and voice 2, simultaneous changes to MIDI and Passersby engine
local function transpose(semitone)
  semi = semitone
end

function wsyn_add_params()
  params:add_group("w/syn",12)
  params:add {
    type = "option",
    id = "wsyn_ar_mode",
    name = "AR mode",
    options = {"off", "on"},
    default = 2,
    action = function(val) 
      crow.send("ii.wsyn.ar_mode(".. (val-1) ..")")
    end
  }
  params:add {
    type = "control",
    id = "wsyn_vel",
    name = "Velocity",
    controlspec = controlspec.new(0, 5, "lin", 0, 2, "v"),
    action = function(val) 
      pset_wsyn_vel = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_curve",
    name = "Curve",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.curve(" .. val .. ")") 
      pset_wsyn_curve = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_ramp",
    name = "Ramp",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.ramp(" .. val .. ")") 
      pset_wsyn_ramp = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_index",
    name = "FM index",
    controlspec = controlspec.new(0, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.fm_index(" .. val .. ")") 
      pset_wsyn_fm_index = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_env",
    name = "FM env",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.fm_env(" .. val .. ")") 
      pset_wsyn_fm_env = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_ratio_num",
    name = "FM ratio numerator",
    controlspec = controlspec.new(1, 20, "lin", 1, 2),
    action = function(val) 
      crow.send("ii.wsyn.fm_ratio(" .. val .. "," .. params:get("wsyn_fm_ratio_den") .. ")") 
      pset_wsyn_fm_ratio_num = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_ratio_den",
    name = "FM ratio denominator",
    controlspec = controlspec.new(1, 20, "lin", 1, 1),
    action = function(val) 
      crow.send("ii.wsyn.fm_ratio(" .. params:get("wsyn_fm_ratio_num") .. "," .. val .. ")") 
      pset_wsyn_fm_ratio_den = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_lpg_time",
    name = "LPG time",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.lpg_time(" .. val .. ")") 
      pset_wsyn_lpg_time = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_lpg_symmetry",
    name = "LPG symmetry",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.lpg_symmetry(" .. val .. ")") 
      pset_wsyn_lpg_symmetry = val
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_pluckylog",
    name = "Pluckylogger >>>",
    action = function()
      params:set("wsyn_curve", math.random(-40, 40)/10)
      params:set("wsyn_ramp", math.random(-5, 5)/10)
      params:set("wsyn_fm_index", math.random(-50, 50)/10)
      params:set("wsyn_fm_env", math.random(-50, 40)/10)
      params:set("wsyn_fm_ratio_num", math.random(1, 4))
      params:set("wsyn_fm_ratio_den", math.random(1, 4))
      params:set("wsyn_lpg_time", math.random(-28, -5)/10)
      params:set("wsyn_lpg_symmetry", math.random(-50, -30)/10)
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_randomize",
    name = "Randomize all >>>",
    action = function()
      params:set("wsyn_curve", math.random(-50, 50)/10)
      params:set("wsyn_ramp", math.random(-50, 50)/10)
      params:set("wsyn_fm_index", math.random(0, 50)/10)
      params:set("wsyn_fm_env", math.random(-50, 50)/10)
      params:set("wsyn_fm_ratio_num", math.random(1, 20))
      params:set("wsyn_fm_ratio_den", math.random(1, 20))
      params:set("wsyn_lpg_time", math.random(-50, 50)/10)
      params:set("wsyn_lpg_symmetry", math.random(-50, 50)/10)
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_init",
    name = "Init",
    action = function()
      params:set("wsyn_curve", pset_wsyn_curve)
      params:set("wsyn_ramp", pset_wsyn_ramp)
      params:set("wsyn_fm_index", pset_wsyn_fm_index)
      params:set("wsyn_fm_env", pset_wsyn_fm_env)
      params:set("wsyn_fm_ratio_num", pset_wsyn_fm_ratio_num)
      params:set("wsyn_fm_ratio_den", pset_wsyn_fm_ratio_den)
      params:set("wsyn_lpg_time", pset_wsyn_lpg_time)
      params:set("wsyn_lpg_symmetry", pset_wsyn_lpg_symmetry)
      params:set("wsyn_vel", pset_wsyn_vel)
    end
  }
  params:hide("wsyn_init")
end

function pulse()
  while true do
    clock.sync(1/ppqn)
    ppqn_counter = ppqn_counter + 1
    iterate()
  end
end

function init_olafur(x)
  olafur_in = midi.connect(x)
  olafur_in.event = function(data)
    local d = midi.to_msg(data)
    if params:string("scale") == "olafur" then
      if d.type == "note_on" then
        if tab.count(notes[coll]) > 0 and active_olafur_notes == 0 then
          notes[coll] = {}
        end
        active_olafur_notes = active_olafur_notes + 1
        table.insert(notes[coll],d.note-48)
      elseif d.type == "note_off" and params:get("olafur_hold") == 0 then
        for i = #notes[coll], 1, -1 do
          if notes[coll][i] == d.note-48 then
            table.remove(notes[coll], i)
            active_olafur_notes = active_olafur_notes - 1
          end
        end
      end
      new_high = #notes[coll]
      if new_low > #notes[coll] then
        new_low = 1
      end
    end
  end
end

-- everything that happens when the script is first loaded
function init()
  -- sets initial state
  crow.send("ii.wsyn.ar_mode(1)")
  voice[1].bit = 1
  voice[2].bit = 8
  seed = 36
  rule = 30
  new_seed = seed
  new_rule = rule

  press_counter = {}
  momentary = {}

  for x = 1,16 do
    momentary[x] = {}
    for y = 1,8 do
      momentary[x][y] = false
    end
  end

  display_voice[1] = false
  display_voice[2] = false
  
  math.randomseed(os.time())
  math.random(); math.random(); math.random()
  seed_to_binary()
  rule_to_binary()

  params.action_write = function(filename, name, pset_number)
    if pset_number == nil then
      clock.run(function()
        clock.sleep(0.25)
        local file = io.open(norns.state.data.."pset-last.txt", "r")
        if file then
          io.input(file)
          pset_number = string.format("%02d",io.read())
          savestate(pset_number)
          io.close(file)
        end
      end)
    else
      savestate(pset_number)
    end
  end
  params.action_read = function(filename, silent, pset_number)
    if pset_number == nil then
      clock.run(function()
        clock.sleep(0.25)
        local file = io.open(norns.state.data.."pset-last.txt", "r")
        if file then
          io.input(file)
          pset_number = string.format("%02d",io.read())
          loadstate(pset_number)
          io.close(file)
        end
      end)
    else
      loadstate(pset_number)
    end
  end
  params.action_delete = function(filename, name, pset_number)
    if pset_number == nil then
      clock.run(function()
        clock.sleep(0.25)
        local file = io.open(norns.state.data.."pset-last.txt", "r")
        if file then
          io.input(file)
          pset_number = string.format("%02d",io.read())
          norns.system_cmd("rm -r "..norns.state.data.."/"..pset_number.."/")
          io.close(file)
        end
      end)
    else
      norns.system_cmd("rm -r "..norns.state.data.."/"..pset_number.."/")
    end
  end

  params:add_separator("less concepts")

  params:add_group("historical load", 3)
  params:add_separator("AS OF APRIL 2022, USE PSETS")
  params:add_number("set", "set", 1,100,1)
  params:set_action("set", function (x) selected_set = x end)
  params:add{type = "trigger", id = "load", name = "load", action = historical_loadstate}

  params:add_group("time, midi & outputs", 32)
  params:add_separator("time (locked with presets)")
  params:add_option("time_div_opt", "time range", {"legacy 1/8 - 1/32", "slow 1/1 - 1/16", "full 2/1 - 1/32"}, 1)
  params:set_action("time_div_opt", function(x)
    if preset_count == 0 then
      selected_time_param = x
      ppqn_divisions = ppqn_divisions_variants[selected_time_param]
      ppqn_names = ppqn_names_variants[selected_time_param]
      if all_loaded then
        sel_ppqn_div = util.round((1+#ppqn_divisions)/2)
      end

      grid_dirty = true
    else
      params:set("time_div_opt", selected_time_param)
    end
  end)
  params:add_number("p_duration", "default length (cycle): ", 1, 32, 4)
  p_duration = params:get("p_duration")

  params:add_separator("midi")
  midi_device_names = {}
  for i = 1,#midi.vports do -- query all ports
    table.insert(midi_device_names,"port "..i..": "..util.trim_string_to_width(midi.vports[i].name,48)) -- register its name
  end

  params:add_binary("olafur_enabled","enable olafur mode","toggle")
  params:set_action("olafur_enabled", function(x)
    if x == 0 then
      params:hide("olafur_device")
      params:hide("olafur_hold")
      params:hide("olafur_panic")
      params:hide("olafur_snapshot")
      if all_loaded then
        if pre_olafur ~= nil and pre_olafur.scale ~= nil then
          params:set("scale",pre_olafur.scale)
          new_low = pre_olafur.low
          new_high = pre_olafur.high
        else
          params:set("scale",1)
          new_low = 1
          new_high = 14
        end
      end
    else
      pre_olafur= {}
      pre_olafur.scale = params:get("scale")
      pre_olafur.low = new_low
      pre_olafur.high = new_high
      params:show("olafur_device")
      params:show("olafur_hold")
      params:show("olafur_panic")
      params:show("olafur_snapshot")
      params:set("scale",tab.key(params.params[params.lookup["scale"]].options,"olafur"))
    end
    _menu.rebuild_params()
  end)
  params:add_option("olafur_device","--> device",midi_device_names,1)
  params:set_action("olafur_device", function(x)
    if params:string("scale") == "olafur" then
      init_olafur(x)
    end
  end)
  params:add_binary("olafur_hold","--> hold","toggle")
  params:set_action("olafur_hold",function(x)
    if x == 0 and params:string("scale") == "olafur" then
      notes[coll] = {}
      new_low = 1
      new_high = 0
      force_notes_off()
    end
  end)
  params:add_binary("olafur_panic","--> panic","momentary")
  params:set_action("olafur_panic",function()
    if params:string("scale") == "olafur" then
      notes[coll] = {}
      new_low = 1
      new_high = 0
      active_olafur_notes = 0
      force_notes_off()
    end
  end)
  params:add_option("olafur_snapshot","--> save with snapshots",{"off","on"},1)

  params:add_option("midi_device", "midi (out)", midi_device_names, 1)
  params:set_action("midi_device", function (x) m = midi.connect(x) end)
  params:add_binary("midi_device_in_enabled","enable midi note in control","toggle")
  params:set_action("midi_device_in_enabled", function(x)
    if x == 0 then
      params:hide("midi_device_in")
    else
      params:show("midi_device_in")
    end
    _menu.rebuild_params()
  end)
  params:add_option("midi_device_in", "midi (in)", midi_device_names, 2)
  params:set_action("midi_device_in", function(x)
    if params:get("midi_device_in_enabled") == 1 then
      midi_in = midi.connect(x)
      midi_in.event = function(data)
        local d = midi.to_msg(data)
        if d.type == "note_on" then
          if params:get("midi_seq_root") + preset_count >= d.note + 1 then
            selected_preset = util.clamp(d.note - params:get("midi_seq_root") + 2, 1, preset_count)
            new_preset_unpack(selected_preset)
          end
        end
      end
    end
  end)
  params:add_number("midi_A", "midi ch A", 1,16,1)
  params:add_number("midi_B", "midi ch B", 1,16,1)
  params:add_option("midi_transport", "start/stop with transport", {"off", "on"}, 2)
  params:set_action("midi_transport", function (x) 
    -- if x == 1 then transport_run = true end
  end)
  midi_seq_note_list = {}
  for i=0,127 do
    table.insert(midi_seq_note_list, MusicUtil.note_num_to_name(i,true))
  end
  params:add_option("midi_seq_root","midi -> snapshots root", midi_seq_note_list,61)
  params:add_separator("voice 1 outputs")
  params:add_option("voice_1_engine", "vox 1 -> engine", {"no", "yes"}, 2)
  params:add_option("voice_1_midi_A", "vox 1 -> midi ch A", {"no", "yes"}, 1)
  params:add_option("voice_1_midi_B", "vox 1 -> midi ch B", {"no", "yes"}, 1)
  params:add_option("voice_1_crow_1", "vox 1 -> crow 1/2", {"no", "yes"}, 1)
  params:set_action("voice_1_crow_1", function (x)
    crow.output[2].action = "{to(".. crow_gate_volts ..",0),to(0,".. crow_gate_length .. ")}" 
  end)
  params:add_option("voice_1_crow_2", "vox 1 -> crow 3/4", {"no", "yes"}, 1)
  params:set_action("voice_1_crow_2", function (x)
    crow.output[4].action = "{to(".. crow_gate_volts ..",0),to(0,".. crow_gate_length .. ")}" 
  end)
  params:add_option("voice_1_JF", "vox 1 -> JF", {"no", "yes"}, 1)
  params:set_action("voice_1_JF", function(x)
    if params:get("voice_2_JF") == 1 then
      if x == 2 then
        crow.ii.jf.mode(1)
      else
        crow.ii.jf.mode(0)
      end
    end
  end)
  params:add_option("voice_1_w", "vox 1 -> w/syn", {"no", "yes"}, 1)
  params:add_separator("voice 2 outputs")
  params:add_option("voice_2_engine", "vox 2 -> engine", {"no", "yes"}, 2)
  params:add_option("voice_2_midi_A", "vox 2 -> midi ch A", {"no", "yes"}, 1)
  params:add_option("voice_2_midi_B", "vox 2 -> midi ch B", {"no", "yes"}, 1)
  params:add_option("voice_2_crow_1", "vox 2 -> crow 1/2", {"no", "yes"}, 1)
  params:set_action("voice_2_crow_1", function (x)
    crow.output[2].action = "{to(".. crow_gate_volts ..",0),to(0,".. crow_gate_length .. ")}" 
  end)
  params:add_option("voice_2_crow_2", "vox 2 -> crow 3/4", {"no", "yes"}, 1)
  params:set_action("voice_2_crow_2", function (x)
    crow.output[4].action = "{to(".. crow_gate_volts ..",0),to(0,".. crow_gate_length .. ")}" 
  end)
  params:add_option("voice_2_JF", "vox 2 -> JF", {"no", "yes"}, 1)
  params:set_action("voice_2_JF", function(x)
    if params:get("voice_1_JF") == 1 then
      if x == 2 then
        crow.ii.jf.mode(1)
      else
        crow.ii.jf.mode(0)
      end
    end
  end)
  params:add_option("voice_2_w", "vox 2 -> w/syn", {"no", "yes"}, 1)

  params:add_group("scaling & randomization",19)
  params:add_option("scale", "scale", names, 1)
  params:set_action("scale", function(x)
    if params:string("scale") == "olafur" then
      new_low = 1
      new_high = 1
      notes[x] = {}
      init_olafur(params:get("olafur_device"))
      force_notes_off()
    end
    coll = x
  end)
  params:add_number("global transpose", "global transpose", -24,24,0)
  params:set_action("global transpose", function (x) transpose(x) end)
  for i = 1,2 do
    params:add_control("transpose "..i, "transpose "..i, controlspec.new(-24,24,'lin',1,12,'s/t'))
    params:set_action("transpose "..i, function(x) random_note[i].tran = x end)
    params:add_control("tran prob "..i, "tran prob "..i, controlspec.new(0,100,'lin',1,0,'%'))
    params:set_action("tran prob " ..i, function(x) random_note[i].probability = x end)
  end
  for i = 1,2 do
    params:add_control("gate prob "..i, "gate prob "..i, controlspec.new(0,100,'lin',1,100,'%'))
    params:set_action("gate prob "..i, function(x) random_gate[i].probability = x end)
  end
  params:add_separator("randomization limits")
  params:add_number("seed_clamp_min", "seed min", 0, 255, 0)
  params:add_number("seed_clamp_max", "seed max", 0, 255, 255)
  params:add_number("rule_clamp_min", "rule min", 0, 255, 0)
  params:add_number("rule_clamp_max", "rule max", 0, 255, 255)
  params:set_action("seed_clamp_min", function(x) 
    if x >= params:get("seed_clamp_max") then
      params:set("seed_clamp_min", params:get("seed_clamp_max") - 1)
    end
  end)
  params:set_action("seed_clamp_max", function(x) 
    if x <= params:get("seed_clamp_min") then
      params:set("seed_clamp_max", params:get("seed_clamp_min") + 1)
    end
  end)
  params:set_action("rule_clamp_min", function(x)
    if x >= params:get("rule_clamp_max") then
      params:set("rule_clamp_min", params:get("rule_clamp_max") - 1)
    end
  end)
  params:set_action("rule_clamp_max", function(x)
    if x <= params:get("rule_clamp_min") then
      params:set("rule_clamp_max", params:get("rule_clamp_min") + 1)
    end
  end)
  
  params:add_number("lo_clamp_min", "low min", 1, 32, 1)
  params:add_number("lo_clamp_max", "low max", 1, 32, 32)
  params:add_number("hi_clamp_min", "high min", 1, 32, 1)
  params:add_number("hi_clamp_max", "high max", 1, 32, 32)
  params:set_action("lo_clamp_min", function(x) 
    if x >= params:get("lo_clamp_max") then
      params:set("lo_clamp_min", params:get("lo_clamp_max") - 1)
    end
  end)
  params:set_action("lo_clamp_max", function(x) 
    if x <= params:get("lo_clamp_min") then
      params:set("lo_clamp_max", params:get("lo_clamp_min") + 1)
    end
  end)
  params:set_action("hi_clamp_min", function(x) 
    if x >= params:get("hi_clamp_max") then
      params:set("hi_clamp_min", params:get("hi_clamp_max") - 1)
    end  
  end)
  params:set_action("hi_clamp_max", function(x) 
    if x <= params:get("hi_clamp_min") then
      params:set("hi_clamp_max", params:get("hi_clamp_min") + 1)
    end  
  end)

  params:add_number("oct_clamp_min", "octave min", -3, 3, -2)
  params:add_number("oct_clamp_max", "octave max", -3, 3, 2)
  params:set_action("oct_clamp_min", function(x) 
    if x >= params:get("oct_clamp_max") then
      params:set("oct_clamp_min", params:get("oct_clamp_max") - 1)
    end  
  end)
  params:set_action("oct_clamp_max", function(x) 
    if x <= params:get("oct_clamp_min") then
      params:set("oct_clamp_max", params:get("oct_clamp_min") + 1)
    end  
  end)
  
  refrain.init()
  
  params:add_group("passersby", 31)
  passersby.add_params()
  wsyn_add_params()
  params:bang()
  params:set("wsyn_init",1)

  bang()

  clock.run(pulse)

  grid_dirty = true
  clock.run(redraw_clock)

  all_loaded = true

end 

-- this section is all hardware stuff
-- hardware: key interaction
function key(n,z)
  is_cycle_editing = (string.find(cycle_sel, "*") ~= nil)
  if n == 1 and z == 1 then
    screen_focus = screen_focus + 1
  end
  -----
  if screen_focus % 2 == 1 then
    if n == 2 and z == 1 then
      KEY2 = true
      bang()
      if preset_count <= 16  and edit ~= "presets" then
        preset_count = preset_count + 1
        new_preset_pack(preset_count)
        selected_preset = 1 -- FIX!
        grid_dirty = true
      elseif preset_count <= 16 and preset_count > 0 and edit == "presets" then
        new_preset_unpack(selected_preset)
      end
    elseif n == 2 and z == 0 then
      KEY2 = false
      bang()
    end
    if n == 3 and z == 1 then
      KEY3 = true
      if KEY2 == false then
        if edit == "cycle" then
          
          if cycle_sel ~= "-" and string.find(cycle_sel, "*") == nil then
              cycle_sel = cycle_sel .. "*"
            else
              cycle_sel = string.sub(cycle_sel, 1, 1)
            end
        elseif edit ~= "presets" then
          randomize_some()
        else
          randomize_all()
        end
      else
        if preset_count == 1 then
          if edit == "presets" then
            edit = "seed/rule"
            dd = 2
          end
        end
        preset_remove(selected_preset)
        for i=1,8 do
          g:led(i,8,0)
        end
        grid_dirty = true
      end
    elseif n == 3 and z == 0 then
      KEY3 = false
      bang()
    end
    --redraw()
    screen_dirty = true
  elseif screen_focus % 2 == 0 then
  -- PUT OTHER SCRIPT HARDWARE CONTROLS HERE
    refrain.key(n,z)
  end
end

-- hardware: encoder interaction
function enc(n,d)
  if screen_focus % 2 == 1 then
    if n == 1 then
      if preset_count > 0 then
        dd = util.clamp(dd+d,1,9)
        edit = edit_foci[dd]
      else
        dd = util.clamp(dd+d,1,8)
        edit = edit_foci[dd]
      end
    end
    if KEY3 == false and KEY2 == false then
      if n == 2 then
        if edit == "presets" and selected_preset > 0 then
          selected_preset = util.clamp(selected_preset+d,1,preset_count)
          p_duration = new_preset_pool[selected_preset].p_duration
          --new_preset_unpack(selected_preset)
        elseif edit == "rand_prob" then
          params:set("tran prob 1", math.min(100,(math.max(params:get("tran prob 1") + d,0))))
        elseif edit == "lc_gate_probs" then
          params:set("gate prob 1", math.min(100,(math.max(params:get("gate prob 1") + d,0))))
        elseif edit == "low/high" and params:string("scale") ~= "olafur" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].new_low = math.min(32,(math.max(new_preset_pool[selected_preset].new_low + d,1)))
          end
            new_low = math.min(32,(math.max(new_low + d,1)))
        elseif edit == "octaves" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].v1_octave = math.min(3,(math.max(new_preset_pool[selected_preset].v1_octave + d,-3)))
          end
            voice[1].octave = math.min(3,(math.max(voice[1].octave + d,-3)))
          
          for i=10,16 do
            g:led(i,1,0)
            g:led(voice[1].octave+13,1,15)
            grid_dirty = true
          end
        elseif edit == "lc_bits" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].v1_bit = math.min(8,(math.max(new_preset_pool[selected_preset].v1_bit - d,0)))
          end
            voice[1].bit = math.min(8,(math.max(voice[1].bit - d,0)))
        elseif edit == "seed/rule" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].seed = math.min(255,(math.max(new_preset_pool[selected_preset].seed + d,0)))
          end
            new_seed = math.min(255,(math.max(new_seed + d,0)))
            seed = new_seed
            rule = new_rule
            bang()
        elseif edit == "cycle" and preset_count > 0 then
          local current_cycle_mode = 1
          for i=1,#cycle_modes do
            if cycle_sel == cycle_modes[i] then
              current_cycle_mode = i
            end
          end
          if cycle_sel == "*" then
            cycle_sel = cycle_modes[util.clamp(current_cycle_mode + d, 1, 2)]
          elseif string.find(cycle_sel, "*") == nil then
            cycle_sel = cycle_modes[util.clamp(current_cycle_mode + d, 1, #cycle_modes - 3)]
          else
            cycle_sel = cycle_modes[util.clamp(current_cycle_mode + d, #cycle_modes - 2, #cycle_modes)]
          end
        elseif edit == "clock" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].sel_ppqn_div = util.clamp(new_preset_pool[selected_preset].sel_ppqn_div + d, 1, #ppqn_divisions)  
          end
            sel_ppqn_div = util.clamp(sel_ppqn_div + d, 1, #ppqn_divisions)
          --redraw()  
          screen_dirty = true
        end
          --redraw()
          screen_dirty = true
      elseif n == 3 then
        if edit == "lc_gate_probs" then
          params:set("gate prob 2", math.min(100,(math.max(params:get("gate prob 2") + d,0))))
        elseif edit == "rand_prob" then
          params:set("tran prob 2", math.min(100,(math.max(params:get("tran prob 2") + d,0))))
        elseif edit == "low/high" and params:string("scale") ~= "olafur" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].new_high = math.min(32,(math.max(new_preset_pool[selected_preset].new_high + d,1)))
          end
            new_high = math.min(32,(math.max(new_high + d,1)))
          
          for i=1,16 do
            g:led(i,6,0)
            g:led(i,7,0)
            if new_high < 17 then
              g:led(new_high,6,15)
            elseif new_high > 16 then
              g:led(new_high-16,7,15)
            end
            grid_dirty = true
          end
        elseif edit == "octaves" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].v2_octave = math.min(3,(math.max(new_preset_pool[selected_preset].v2_octave + d,-3)))
          end
          voice[2].octave = math.min(3,(math.max(voice[2].octave + d,-3)))
          
          for i=10,16 do
            g:led(i,2,0)
            g:led(voice[2].octave+13,2,15)
            grid_dirty = true
          end
        elseif edit == "lc_bits" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].v2_bit = math.min(8,(math.max(new_preset_pool[selected_preset].v2_bit - d,0)))
          end
          voice[2].bit = math.min(8,(math.max(voice[2].bit - d,0)))
          
        elseif edit == "seed/rule" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].rule = math.min(255,(math.max(new_preset_pool[selected_preset].rule + d,0)))
          end
            new_rule = math.min(255,(math.max(new_rule + d,0)))
            rule = new_rule
            seed = new_seed
            bang()

        elseif edit == "clock" then
          if string.find(cycle_sel, "*") ~= nil then
            new_preset_pool[selected_preset].sel_ppqn_div = util.clamp(new_preset_pool[selected_preset].sel_ppqn_div + d, 1, #ppqn_divisions)  
          end
          sel_ppqn_div = util.clamp(sel_ppqn_div + d, 1, #ppqn_divisions)

        elseif edit == "cycle" and preset_count > 0 then
          if string.find(cycle_sel, "*") ~= nil then
            p_duration = util.clamp(p_duration + d, 1, 32)
            new_preset_pool[selected_preset].p_duration = util.clamp(new_preset_pool[selected_preset].p_duration + d, 1, 32)
          end
        end
        --redraw()
        screen_dirty = true
      end
    end
    --redraw()
    screen_dirty = true
  elseif screen_focus % 2 == 0 then
    --PUT OTHER SCRIPT ENC CONTROLS HERE
    refrain.enc(n,d)
  end
end

-- hardware: screen redraw
function redraw()
  if screen_focus % 2 == 1 then
    if edit == "presets" and preset_count > 0 and string.find(cycle_sel, "*") ~= nil then
      seed_string = new_preset_pool[selected_preset].seed
      rule_string = new_preset_pool[selected_preset].rule
      lo_string = new_preset_pool[selected_preset].new_low
      hi_string = new_preset_pool[selected_preset].new_high
      v1oct_string = new_preset_pool[selected_preset].v1_octave
      v2oct_string = new_preset_pool[selected_preset].v2_octave
      v1_b = new_preset_pool[selected_preset].v1_bit
      v2_b = new_preset_pool[selected_preset].v2_bit
      ppqn_string = ppqn_names[new_preset_pool[selected_preset].sel_ppqn_div]
      p_dur_string = new_preset_pool[selected_preset].p_duration
    else
      seed_string = new_seed
      rule_string = new_rule
      lo_string = new_low
      hi_string = new_high
      v1oct_string = voice[1].octave
      v2oct_string = voice[2].octave
      ppqn_string = ppqn_names[sel_ppqn_div]
      v1_b = voice[1].bit
      v2_b = voice[2].bit
      if preset_count > 0 and selected_preset ~= 0 then
        p_dur_string = new_preset_pool[selected_preset].p_duration
      else
        p_dur_string = p_duration
      end
    end
    screen.font_face(1)
    screen.font_size(8)
    screen.clear()
    screen.level(15)
    screen.move(0,10)

    local highlight = edit == "lc_bits" and 15 or 4
    for i = 0,7 do
      bit = seed_as_binary[8-i]
      if bit == 1 then
       screen.level(highlight)
      else
       screen.level(1)
      end
      screen.rect(5*i,2,4,4)
      screen.fill()
    end
    
    screen.level(edit == "lc_bits" and 15 or 2)
    screen.line_width(1)
    screen.move(5*8-5*(v1_b),1)
    screen.line_rel(4,0)
    screen.move(5*8-5*(v2_b),8)
    screen.line_rel(4,0)
    screen.stroke()
    
    screen.move(48,8)
    screen.level(edit == "seed/rule" and 15 or 2)
    screen.text("s: "..seed_string.." // r: "..rule_string)
    screen.level(edit == "octaves" and 15 or 2)
    screen.move(48,16)
    screen.text("oct 1: "..v1oct_string.." // 2: "..v2oct_string)
    screen.move(48,24)
    screen.level(edit == "low/high" and 15 or 2)
    screen.text("low: "..lo_string.." // high: "..hi_string)
    screen.move(48,32)
    screen.level(edit == "clock" and 15 or 2)
    screen.text("time: "..ppqn_string)
    
    screen.level(edit == "lc_gate_probs" and 15 or 2)
    screen.move(3,41)
    screen.text("gate prob")
    screen.move(48,41)
    screen.text("1: "..params:get("gate prob 1").."% // 2: "..params:get("gate prob 2").."%")
    screen.level(edit == "rand_prob" and 15 or 2)
    screen.move(3,49)
    screen.text("tran prob")
    screen.move(48,49)
    screen.text("1: "..params:get("tran prob 1").."% // 2: "..params:get("tran prob 2").."%")

    for i = 1,2 do
      for j = 1,8 do
        if edit == "presets" then screen.level(2) else screen.level(1) end
        if j + ((i-1)*8) <= preset_count then
          screen.level(4)
        end
        if j + ((i-1)*8) == selected_preset and preset_count > 0 then
          screen.level(edit == "presets" and 15 or 8)
        end
        screen.rect((j-1)*5,54 + (i-1)*5,4,4)
        screen.fill()
      end
    end

    gridplay_active = false
    for y = 4,5 do
      for x = 1,16 do
        if momentary[x][y] == true then
          gridplay_active = true
          break
        end
      end
    end

    --draw durrently triggered note
    screen.font_size(24)
    screen.move(4, 32)
    screen.level(1)
    if screennote ~= nil then
      screen.text(MusicUtil.note_num_to_name(screennote))
      screen.move(5, 30)
      screen.level(8)
      screen.text(MusicUtil.note_num_to_name(screennote))
    end

    --cycle mode and preset duration
    screen.font_size(8)
    screen.level(edit == "cycle" and 15 or 2)
    screen.move(48,60)
    screen.text(cycle_sel)
    screen.move(60,60)
    if selected_preset > 0 and preset_count > 0 then
      screen.text("s"..selected_preset.." length: x".. p_dur_string)
    end

    screen.update()
  elseif screen_focus%2==0 then
    -- PUT OTHER SCREEN REDRAW HERE
    refrain.redraw()
  end
end

-- hardware: grid connect

-- local grid;
grid_checker = {}
for i = 1,4 do
  grid_checker[i] = grid.vports[i].name
end

function check_for_monome_grid()
  -- for _,value in pairs(grid_checker) do
  --   if value ~= "none" then
  --     return true
  --   end
  -- end
  -- return false

  if tab.count(grid.devices) == 0 then
    return false
  else
    return true
  end
end

function return_midigrid_size()
  if midigrid_size == 64 then
    return "midigrid/lib/midigrid"
  else
    return "midigrid/lib/mg_128"
  end
end

local grid = (util.file_exists(_path.code.."midigrid") and not check_for_monome_grid()) and include (return_midigrid_size()) or grid
g = grid.connect()

function long_press(x)
  
  clock.sleep(0.5)
  if cycle_sel ~= "-" then
    if cycle_sel == "*" then
      if x == 9 then
        cycle_sel = "<*"
      elseif x == 11 then
        cycle_sel = ">*"
      elseif x == 10 then
        cycle_sel = "~*"
      end
    elseif string.find(cycle_sel, "*") then
      if x == 9 then
        cycle_sel = "<"
      elseif x == 11 then
        cycle_sel = ">"
      elseif x == 10 then
        cycle_sel = "~"
      end
    else
      if x == 9 then
        cycle_sel = "<"
      elseif x == 11 then
        cycle_sel = ">"
      elseif x == 10 then
        cycle_sel = "~"
      end
      cycle_sel = cycle_sel .. "*"
    end
  else
    if x == 9 or x == 10 or x == 11 then
      cycle_sel = "*"
    end
  end
  if selected_preset == 0 then selected_preset = 1 end
  press_counter[x] = nil
end

function short_press(x)
  if string.find(cycle_sel, "*") and cycle_sel ~= "*" then
    is_destructive = true
    if x == 9 then
      cycle_sel = "<*"
      is_destructive = false
    elseif x == 11 then
      cycle_sel = ">*"
      is_destructive = false
    elseif x == 10 then
      cycle_sel = "~*"
      is_destructive = false
    end
  else
    if cycle_sel == "<" and x == 9 then
      cycle_sel = "-"
    elseif cycle_sel == ">" and x == 11 then
      cycle_sel = "-"
    elseif cycle_sel == "~" and x == 10 then
      cycle_sel = "-"
    elseif x == 9 then
      cycle_sel = "<"
    elseif x == 11 then
      cycle_sel = ">"
    elseif x == 10 then
      cycle_sel = "~"
    end
  end
  p_duration_counter = 1
end

-- hardware: grid event (eg 'what happens when a button is pressed')

g.key = function(x,y,z)
  -- buttons for clock divisions
  if g.cols >= 16 then
    if y == 8 and x >= 1 and x <= 3 then
      if y == 8 and x == 1 and z == 1 then
        sel_ppqn_div = util.clamp(sel_ppqn_div - 1, 1, #ppqn_divisions) 
      end
      if y == 8 and x == 2 and z == 1 then
        sel_ppqn_div = math.floor((#ppqn_divisions + 1) / 2)
      end
      if y == 8 and x == 3 and z == 1then
        sel_ppqn_div = util.clamp(sel_ppqn_div + 1, 1, #ppqn_divisions)
      end

    -- buttons for changing cycle modes
    elseif y == 6 and x >= 9 and x <= 11 and preset_count > 0 then
      if z == 1 then
        press_counter[x] = clock.run(long_press, x)
      elseif z == 0 then
        if press_counter[x] then
          clock.cancel(press_counter[x])
          short_press(x)
        end
      end

    --change active bits per voice
    elseif y == 1 and x <= 9 then -- ADDED: <= makes (9,1) mute voice 1
      g:led(x,y,z*15)
      voice[1].bit = 9-x
    elseif y == 1 and x > 9 and z == 1 then
      for i=10,16 do
        g:led(i,1,0)
      end
      g:led(x,y,z*15)
      voice[1].octave = x-13
    elseif y == 2 and x <= 9 then -- ADDED: <= makes (9,2) mute voice 2
      g:led(x,y,z*15)
      voice[2].bit = 9-x
    elseif y == 2 and x > 9 and z == 1 then
      for i=10,16 do
        g:led(i,2,0)
      end
      g:led(x,y,z*15)
      voice[2].octave = x-13
    
    --keys for momentary selecting low/high
    elseif y == 6 and x == 1 then
      g:led(x,y,15)
      momentary[x][y] = z == 1 and true or false
    elseif y == 6 and x == 2 then
      g:led(x,y,15)
      momentary[x][y] = z == 1 and true or false
      grid_dirty = true

    --keys for changing low/high when select is momentary
    elseif (y == 4 or y == 5) and z == 1 then
      if momentary[1][6] then
        if y == 4 then new_low = x
        elseif y == 5 then new_low = x + 16 end
      elseif momentary[2][6] then
        if y == 4 then new_high = x
        elseif y == 5 then new_high = x + 16 end
      end

    --keys for randomization
    elseif y == 3 and z == 1 then
      if x == 1 then
        seed = math.random(params:get("seed_clamp_min"),params:get("seed_clamp_max"))
        new_seed = seed
      elseif x == 2 then
        rule = math.random(params:get("rule_clamp_min"),params:get("rule_clamp_max"))
        new_rule = rule
      elseif x == 4 then
        voice[1].bit = math.random(0,8)
      elseif x == 5 then
        voice[2].bit = math.random(0,8)
      elseif x == 7 or x == 8 or x == 10 or x == 11 then
        if x == 7 then
          new_low = math.random(params:get("lo_clamp_min"),params:get("lo_clamp_max"))
        end
        if x == 8 then
          new_high = math.random(params:get("hi_clamp_min"),params:get("hi_clamp_max"))
        end
        if x == 10 then
          voice[1].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
        end
        if x == 11 then
          voice[2].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
        end
      elseif x == 10 then
        voice[1].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
      elseif x == 11 then
        voice[2].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
      elseif x == 13 then
        sel_ppqn_div = math.random(1, #ppqn_divisions)
      elseif x == 14 then
        sel_ppqn_div = math.random(1, #ppqn_divisions)
        randomize_all()
      elseif x == 16 then
        randomize_all()
      end
      bang()
      --keys for selecting presets
    elseif (y == 8 or y == 7) and z == 1 then
      if x > 8 and x < 17 then
        if y == 7 and x - 8 < preset_count+1 then
          selected_preset = x - 8
          new_preset_unpack(x - 8)
        end
        if y == 8 and x < preset_count+1 then
          selected_preset = x
          new_preset_unpack(x)
        end
        if cycle_sel ~= "-" then
          preset_key_is_held = true
          new_preset_unpack(x - 8)
        end
      end

    --key for removing and adding presets
    elseif y == 6 and x >= 14 and x <= 16 then
      if x == 15 and preset_count > 0 and z == 1 then 
          press_counter[x] = clock.run(remove_wait, x)
      elseif x == 14 and z == 1 then
          press_counter[x] = clock.run(remove_wait, x)
      elseif x == 16 and z == 1 and preset_count < 16 then
      elseif x == 16 and preset_count < 16 then
          preset_count = preset_count + 1
          new_preset_pack(preset_count)
          -- selected_preset = 1
      elseif z == 0 and (x == 14 or x == 15) then
          clock.cancel(press_counter[x])
      end
    elseif (y == 7 or y == 8) and z == 0 then
      if x > 8 and x < 17 and x < preset_count+9 then
        preset_key_is_held = false      
      end
    end
  else
    -- buttons for changing cycle modes
    if y == 6 and x >= 1 and x <= 3 and preset_count > 0 then
      if z == 1 then
        press_counter[x+8] = clock.run(long_press, x+8)
      elseif z == 0 then
        if press_counter[x+8] then
          clock.cancel(press_counter[x+8])
          short_press(x+8)
        end
      end
  
    --change active bits per voice
    elseif (y == 1 or y == 2) and x <= 9 then -- ADDED: <= makes (9,1) mute voice 1
      local _v = y
      g:led(x,y,z*15)
      voice[_v].bit = 9-x
  
    --keys for randomization
    elseif y == 3 and z == 1 then
      if x == 1 then
        seed = math.random(params:get("seed_clamp_min"),params:get("seed_clamp_max"))
        new_seed = seed
      elseif x == 2 then
        rule = math.random(params:get("rule_clamp_min"),params:get("rule_clamp_max"))
        new_rule = rule
      elseif x == 4 then
        voice[1].bit = math.random(0,8)
      elseif x == 5 then
        voice[2].bit = math.random(0,8)
      elseif x == 7 then
        new_low = math.random(params:get("lo_clamp_min"),params:get("lo_clamp_max"))
      elseif x == 8 then
        new_high = math.random(params:get("hi_clamp_min"),params:get("hi_clamp_max"))
      end
    elseif y == 4 and z == 1 then
      if x == 1 or x == 2 then
        voice[x].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
      elseif x == 4 then
        sel_ppqn_div = math.random(1, #ppqn_divisions)
      elseif x == 5 then
        sel_ppqn_div = math.random(1, #ppqn_divisions)
        randomize_all()
      elseif x == 8 then
        randomize_all()
      end
      bang()
  
    --keys for selecting presets
    elseif (y == 8 or y == 7) and z == 1 then
      if y == 7 and x < preset_count + 1 then
        selected_preset = x
        new_preset_unpack(x)
      elseif y == 8 and x + 8 < preset_count + 1 then
        selected_preset = x+8
        new_preset_unpack(x+8)
      end
      if cycle_sel ~= "-" then
        preset_key_is_held = true
        new_preset_unpack(x) -- TODO ???
      end
  
    --key for removing and adding presets
    elseif y == 6 and x >= 6 and x <= 8 then
      if x == 7 and preset_count > 0 and z == 1 then 
          press_counter[x] = clock.run(remove_wait, x+8)
      elseif x == 6 and z == 1 then
          press_counter[x] = clock.run(remove_wait, x+8)
      elseif x == 8 and z == 1 and preset_count < 16 then
      elseif x == 8 and preset_count < 16 then
          preset_count = preset_count + 1
          new_preset_pack(preset_count)
          -- selected_preset = 1
      elseif z == 0 and (x == 6 or x == 7) then
          clock.cancel(press_counter[x])
      end
    elseif (y == 7 or y == 8) and z == 0 then
      if x < preset_count+1 then
        preset_key_is_held = false      
      end
    end
  end
  screen_dirty = true
  grid_dirty = true
end

function remove_wait(x)
  clock.sleep(0.5)
  if x == 15 then
    preset_remove(selected_preset)
  elseif x == 14 then
    preset_count = 0
    cycle_sel = "-"
    selected_preset = 1
  end
end

-- hardware: grid redraw
function redraw_clock()
  while true do
    clock.sleep(1/30)
    if screen_dirty or screen_focus % 2 == 0 then
      redraw()
    end
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
  end
end

function grid_redraw()
  g:all(0)

  if g.cols >= 16 then

    --leds for stream
    for i = 1, 8 do
      if seed_as_binary[i] == 1 then
        g:led(9-i,1,2)
        g:led(9-i,2,2)
      end
    end

    --leds for voices
    g:led(9-voice[1].bit,1,4)
    g:led(9-voice[2].bit,2,4)
    if seed_as_binary[voice[1].bit] == 1 and display_voice[1] then
      g:led(9-voice[1].bit,1,15)
    end
    if seed_as_binary[voice[2].bit] == 1 and display_voice[2] then
      g:led(9-voice[2].bit,2,15)
    end

    --leds for randomization
    g:led(1,3,4)
    g:led(2,3,4)
    g:led(4,3,4)
    g:led(5,3,4)
    g:led(7,3,4)
    g:led(8,3,4)
    g:led(10,3,4)
    g:led(11,3,4)
    g:led(13,3,4)
    g:led(14,3,4)
    g:led(16,3,4)

    --light up all available preses
    for i=7,8 do
      for j=9,16 do
        g:led(j,i,2)
      end
    end

    --light up saved presets
    if preset_count > 0 and preset_count <= 8 then
      for i=1,preset_count do
        g:led(i+8,7,6)
      end
    elseif preset_count > 0 and preset_count <= 16 then
      for i=1,8 do
        g:led(i+8,7,6)
      end
      for i=1,preset_count - 8 do
        g:led(i+8,8,6)
      end
    end
    
    --light up active preset
    if preset_count > 0 and selected_preset > 0 then
      if selected_preset <= 8 then
        g:led(selected_preset+8,7,15)
      else
        g:led(selected_preset,8,15)
      end
    end

    g:led(14,6,2) --clear selected preset
    g:led(15,6,4) --clear all presets
    g:led(16,6,6) --add preset

    --leds for octaves
    g:led(voice[1].octave+13,1,15)
    g:led(voice[2].octave+13,2,15)

    --light up low / high when select is momentary
    if momentary[1][6] then low_highlight = 15 else low_highlight = 6 end
    if momentary[2][6] then high_highlight = 15 else high_highlight = 6 end
    
    --leds for selected low / high
    if new_low <= 16 then
      g:led(new_low,4,low_highlight)
    elseif new_low > 16 then
      g:led(new_low-16,5,low_highlight)
    end
    if new_high <= 16 then
      g:led(new_high,4,high_highlight)
    elseif new_high > 16 then
      g:led(new_high-16,5,high_highlight)
    end

    --draw active note
    if gridnote ~= nil then
      if gridnote <= 16 then
        g:led(gridnote, 4, 2)
      elseif gridnote > 16 and gridnote <= 32 then
        g:led(gridnote - 16, 5, 2)
      end
    end

    --leds for momentary select low/high
    g:led(1,6,low_highlight)
    g:led(2,6,high_highlight)

    --leds for time div buttons
    --thank you @Quixotic7
    local off_temp = util.round(15 / #ppqn_divisions) --creates offset for led_low_temp
    local led_low_temp = off_temp + util.round((1-(sel_ppqn_div/#ppqn_divisions))*15) --calculates led brightness
    local led_high_temp = 15 - util.round((1-(sel_ppqn_div/#ppqn_divisions))*15)
    g:led(1, 8, led_low_temp)
    g:led(2, 8, 8)
    g:led(3, 8, led_high_temp)

    --leds for cycling modes
    if preset_count > 0 then
      g:led(9,6,4)
      g:led(10,6,4)
      g:led(11,6,4)
      if string.find(cycle_sel, "*") ~= nil then
        destructive_highlight = 15
      else
        destructive_highlight = 8
      end
      if string.find(cycle_sel, "<") then
        g:led(9,6,destructive_highlight)
      elseif string.find(cycle_sel, ">") then
        g:led(11,6,destructive_highlight)
      elseif string.find(cycle_sel, "~") then
        g:led(10,6,destructive_highlight)
      end
    end
  else
    for i = 1, 8 do
      if seed_as_binary[i] == 1 then
        g:led(9-i,1,2)
        g:led(9-i,2,2)
      end
    end

    --leds for voices
    g:led(9-voice[1].bit,1,4)
    g:led(9-voice[2].bit,2,4)
    if seed_as_binary[voice[1].bit] == 1 and display_voice[1] then
      g:led(9-voice[1].bit,1,15)
    end
    if seed_as_binary[voice[2].bit] == 1 and display_voice[2] then
      g:led(9-voice[2].bit,2,15)
    end

    --leds for randomization
    g:led(1,3,4)
    g:led(2,3,4)
    g:led(4,3,4)
    g:led(5,3,4)
    g:led(7,3,4)
    g:led(8,3,4)
    g:led(1,4,4)
    g:led(2,4,4)
    g:led(4,4,4)
    g:led(5,4,4)
    g:led(8,4,4)

    --light up all available preses
    for i=7,8 do
      for j=1,8 do
        g:led(j,i,2)
      end
    end

    --light up saved presets
    if preset_count > 0 and preset_count <= 8 then
      for i=1,preset_count do
        g:led(i,7,6)
      end
    elseif preset_count > 0 and preset_count <= 16 then
      for i=1,8 do
        g:led(i,7,6)
      end
      for i=1,preset_count - 8 do
        g:led(i,8,6)
      end
    end
    
    --light up active preset
    if preset_count > 0 and selected_preset > 0 then
      if selected_preset <= 8 then
        g:led(selected_preset,7,15)
      else
        g:led(selected_preset,8,15)
      end
    end

    g:led(6,6,2) --clear selected preset
    g:led(7,6,4) --clear all presets
    g:led(8,6,6) --add preset

    --leds for octaves
    -- g:led(voice[1].octave+13,1,15)
    -- g:led(voice[2].octave+13,2,15)

    --light up low / high when select is momentary
    -- if momentary[1][6] then low_highlight = 15 else low_highlight = 6 end
    -- if momentary[2][6] then high_highlight = 15 else high_highlight = 6 end
    
    --leds for selected low / high
    -- if new_low <= 16 then
    --   g:led(new_low,4,low_highlight)
    -- elseif new_low > 16 then
    --   g:led(new_low-16,5,low_highlight)
    -- end
    -- if new_high <= 16 then
    --   g:led(new_high,4,high_highlight)
    -- elseif new_high > 16 then
    --   g:led(new_high-16,5,high_highlight)
    -- end

    --draw active note
    -- if gridnote ~= nil then
    --   if gridnote <= 16 then
    --     g:led(gridnote, 4, 2)
    --   elseif gridnote > 16 and gridnote <= 32 then
    --     g:led(gridnote - 16, 5, 2)
    --   end
    -- end

    --leds for momentary select low/high
    -- g:led(1,6,low_highlight)
    -- g:led(2,6,high_highlight)

    --leds for time div buttons
    --thank you @Quixotic7
    -- local off_temp = util.round(15 / #ppqn_divisions) --creates offset for led_low_temp
    -- local led_low_temp = off_temp + util.round((1-(sel_ppqn_div/#ppqn_divisions))*15) --calculates led brightness
    -- local led_high_temp = 15 - util.round((1-(sel_ppqn_div/#ppqn_divisions))*15)
    -- g:led(1, 8, led_low_temp)
    -- g:led(2, 8, 8)
    -- g:led(3, 8, led_high_temp)

    --leds for cycling modes
    if preset_count > 0 then
      g:led(1,6,4)
      g:led(2,6,4)
      g:led(3,6,4)
      if string.find(cycle_sel, "*") ~= nil then
        destructive_highlight = 15
      else
        destructive_highlight = 8
      end
      if string.find(cycle_sel, "<") then
        g:led(1,6,destructive_highlight)
      elseif string.find(cycle_sel, ">") then
        g:led(3,6,destructive_highlight)
      elseif string.find(cycle_sel, "~") then
        g:led(2,6,destructive_highlight)
      end
    end
  end

  g:refresh()
end

-- this section is all performative stuff

-- randomize all maths paramaters (does not affect scale or engine, for ease of use)
function randomize_all()
  grid_dirty = true
  seed = math.random(params:get("seed_clamp_min"),params:get("seed_clamp_max"))
  new_seed = seed
  rule = math.random(params:get("rule_clamp_min"),params:get("rule_clamp_max"))
  new_rule = rule
  voice[1].bit = math.random(0,8)
  voice[2].bit = math.random(0,8)
  if params:string("scale") == "olafur" and #notes[coll] ~= 0 then
    new_low = math.random(1,#notes[coll])
    new_high = math.random(1,#notes[coll])
  elseif params:string("scale") ~= "olafur" then
    new_low = math.random(params:get("lo_clamp_min"),params:get("lo_clamp_max"))
    new_high = math.random(params:get("hi_clamp_min"),params:get("hi_clamp_max"))
  end
  voice[1].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
  voice[2].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
  bang()
  grid_dirty = true
end

function randomize_some()
  if edit == "seed/rule" then
    seed = math.random(params:get("seed_clamp_min"),params:get("seed_clamp_max"))
    new_seed = seed
    rule = math.random(params:get("rule_clamp_min"),params:get("rule_clamp_max"))
    new_rule = rule
  elseif edit == "lc_gate_probs" then
    for i = 1,2 do
      params:set("gate prob "..i, math.random(0,100))
    end
  elseif edit == "low/high" and params:string("scale") ~= "olafur" then
    new_low = math.random(params:get("lo_clamp_min"),params:get("lo_clamp_max"))
    new_high = math.random(params:get("hi_clamp_min"),params:get("hi_clamp_max"))
  elseif edit == "rand_prob" then
    for i = 1,2 do
      params:set("tran prob "..i, math.random(0,100))
    end
  elseif edit == "octaves" then
    voice[1].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
    voice[2].octave = math.random(params:get("oct_clamp_min"),params:get("oct_clamp_max"))
  elseif edit == "lc_bits" then
    voice[1].bit = math.random(0,8)
    voice[2].bit = math.random(0,8)
  elseif edit == "clock" then
    sel_ppqn_div = math.random(1, #ppqn_divisions)
  elseif edit == "presets" then
    randomize_all()
  end
  bang()
  grid_dirty = true
end

-- pack all maths parameters into a volatile preset

function deep_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
        copy[deep_copy(orig_key)] = deep_copy(orig_value)
    end
    setmetatable(copy, deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

function new_preset_pack(set)
  new_preset_pool[set].seed = new_seed
  new_preset_pool[set].rule = new_rule
  new_preset_pool[set].v1_bit = voice[1].bit
  new_preset_pool[set].v2_bit = voice[2].bit
  new_preset_pool[set].new_low = new_low
  new_preset_pool[set].new_high = new_high
  new_preset_pool[set].v1_octave = voice[1].octave
  new_preset_pool[set].v2_octave = voice[2].octave
  new_preset_pool[set].sel_ppqn_div = sel_ppqn_div
  new_preset_pool[set].p_duration = p_duration
  if params:string("olafur_snapshot") == "on" then
    new_preset_pool[set].olafur_notes = deep_copy(notes[coll])
  end
  selected_preset = set
end

function new_preset_unpack(set)
  if type(new_preset_pool[set].seed) ~= "table" then
    new_seed = new_preset_pool[set].seed
    seed = new_seed
    new_rule = new_preset_pool[set].rule
    rule = new_rule
    voice[1].bit = new_preset_pool[set].v1_bit
    voice[2].bit = new_preset_pool[set].v2_bit
    if (params:string("scale") ~= "olafur") or (params:string("scale") == "olafur" and params:string("olafur_snapshot") == "on") then
      new_low = new_preset_pool[set].new_low
      new_high = new_preset_pool[set].new_high
    end
    voice[1].octave = new_preset_pool[set].v1_octave
    voice[2].octave = new_preset_pool[set].v2_octave
    sel_ppqn_div = new_preset_pool[set].sel_ppqn_div
    p_duration = new_preset_pool[set].p_duration
    p_duration_counter = 1
    if params:string("olafur_snapshot") == "on" then
      notes[coll] = deep_copy(new_preset_pool[set].olafur_notes)
    end
    bang()
    grid_dirty = true
  end
end

function preset_remove(set)
  if set > 0 then
    for i = set,16 do
      new_preset_pool[i].seed = new_preset_pool[i+1].seed
      new_preset_pool[i].rule = new_preset_pool[i+1].rule
      new_preset_pool[i].v1_bit = new_preset_pool[i+1].v1_bit
      new_preset_pool[i].v2_bit = new_preset_pool[i+1].v2_bit
      new_preset_pool[i].new_low = new_preset_pool[i+1].new_low
      new_preset_pool[i].new_high = new_preset_pool[i+1].new_high
      new_preset_pool[i].v1_octave = new_preset_pool[i+1].v1_octave
      new_preset_pool[i].v2_octave = new_preset_pool[i+1].v2_octave
      new_preset_pool[i].sel_ppqn_div = new_preset_pool[i+1].sel_ppqn_div
      new_preset_pool[i].p_duration = new_preset_pool[i+1].p_duration
    end
    if selected_preset > 0 and selected_preset <= preset_count then
      if KEY2 == true and preset_count > 1 then
        selected_preset = util.clamp(selected_preset - 1, 1, 16)
        new_preset_unpack(selected_preset)
      else
        selected_preset = 0
      end
    --elseif selected_preset == preset_count then
    --  selected_preset = util.clamp(selected_preset - 1, 1, 16)
    end
    preset_count = util.clamp(preset_count - 1, 0, 16)
    screen_dirty = true
    --redraw()
  end
end

-- save snapshots as presets

function savestate(pset_number)
  os.execute("mkdir -p "..norns.state.data.."/"..pset_number.."/")
  -- local dirname = _path.data.."less_concepts_3/"
  -- if os.rename(dirname, dirname) == nil then
  --   os.execute("mkdir " .. dirname)
  -- end
  local file = io.open(norns.state.data.."/"..pset_number.."/script_settings.data", "w+")
  io.output(file)
  io.write("permanence".."\n")
  io.write(preset_count.."\n")
  if preset_count > 0 then
    for i = 1,preset_count do
      io.write(new_preset_pool[i].seed .. "\n")
      io.write(new_preset_pool[i].rule .. "\n")
      io.write(new_preset_pool[i].v1_bit .. "\n")
      io.write(new_preset_pool[i].v2_bit .. "\n")
      io.write(new_preset_pool[i].new_low .. "\n")
      io.write(new_preset_pool[i].new_high .. "\n")
      io.write(new_preset_pool[i].v1_octave .. "\n")
      io.write(new_preset_pool[i].v2_octave .. "\n")
    end
  else
    io.write(new_seed .. "\n")
    io.write(new_rule .. "\n")
    io.write(voice[1].bit .. "\n")
    io.write(voice[2].bit .. "\n")
    io.write(new_low .. "\n")
    io.write(new_high .. "\n")
    io.write(voice[1].octave .. "\n")
    io.write(voice[2].octave .. "\n")
  end
  io.write(params:get("clock_tempo") .. "\n")
  io.write('nil' .. "\n")
  io.write(params:get("midi_A") .. "\n")
  io.write(params:get("midi_B") .. "\n")
  io.write(params:get("scale") .. "\n")
  io.write(params:get("global transpose") .. "\n")
  for i=1,2 do
    io.write(params:get("transpose "..i) .. "\n")
    io.write(params:get("tran prob "..i) .. "\n")
  end
  io.write("LC3\n")
  io.write(params:get("time_div_opt").."\n")
  io.write(selected_time_param .. "\n")
  if preset_count == 0 then
    io.write(sel_ppqn_div .. "\n")
    io.write(p_duration .. "\n")
  else
    if preset_count > 0 then
      for i = 1,preset_count do
        io.write(new_preset_pool[i].sel_ppqn_div .. "\n")
        io.write(new_preset_pool[i].p_duration .. "\n")
      end
    else
      io.write(sel_ppqn_div .. "\n")
      io.write(p_duration .. "\n")
    end
  end
  io.write(cycle_sel .. "\n")
  ref_savestate()
  io.close(file)
  if params:string("scale") == "olafur" then
    tab.save(notes[coll],norns.state.data.."/"..pset_number.."/olafur_notes.data")
    if params:string("olafur_snapshot") == "on" then
      for i = 1,preset_count do
        tab.save(new_preset_pool[i].olafur_notes,norns.state.data.."/"..pset_number.."/olafur_notes"..i..".data")
      end
    end
  end
end

function historical_loadstate()
  local file = io.open(_path.data .. "less_concepts_3/less_concepts-pattern"..selected_set..".data", "r")
  if file then
    io.input(file)
    filetype = io.read()
    if filetype == "permanence" then
      preset_count = tonumber(io.read())
      if preset_count > 0 then
        selected_preset = 1
      else
        selected_preset = 0
      end
      if preset_count > 0 then
        for i = 1,preset_count do
          new_preset_pool[i].seed = tonumber(io.read())
          new_preset_pool[i].rule = tonumber(io.read())
          new_preset_pool[i].v1_bit = tonumber(io.read())
          new_preset_pool[i].v2_bit = tonumber(io.read())
          new_preset_pool[i].new_low = tonumber(io.read())
          new_preset_pool[i].new_high = tonumber(io.read())
          new_preset_pool[i].v1_octave = tonumber(io.read())
          new_preset_pool[i].v2_octave = tonumber(io.read())
        end
      else
        seed = tonumber(io.read())
        rule = tonumber(io.read())
        voice[1].bit = tonumber(io.read())
        voice[2].bit = tonumber(io.read())
        new_low = tonumber(io.read())
        new_high = tonumber(io.read())
        voice[1].octave = tonumber(io.read())
        voice[2].octave = tonumber(io.read())
      end
      load_bpm = tonumber(io.read())
      load_clock = tonumber(io.read())
      load_ch_1 = tonumber(io.read())
      load_ch_2 = tonumber(io.read())
      load_scale = tonumber(io.read())
      load_global_trans = tonumber(io.read())
      load_tran_1 = tonumber(io.read())
      load_tran_prob_1 = tonumber(io.read())
      load_tran_2 = tonumber(io.read())
      load_tran_prob_2 = tonumber(io.read())
      if load_bpm == nil and load_clock == nil and load_ch_1 == nil and 
      load_ch_2 == nil and load_scale == nil and load_global_trans == nil then
        --params:set("clock_tempo", 110)
        --params:set("clock_midi_out", 1)
        params:set("midi_A", 1)
        params:set("midi_B", 1)
        params:set("scale", 1)
        params:set("global transpose", 0)
      else
        --params:set("clock_tempo", load_bpm)
        --params:set("clock_midi_out", load_clock)
        params:set("midi_A", load_ch_1)
        params:set("midi_B", load_ch_2)
        params:set("scale", load_scale)
        params:set("global transpose", load_global_trans)
        params:set("transpose 1", load_tran_1)
        params:set("transpose 2", load_tran_2)
        params:set("tran prob 1", load_tran_prob_1)
        params:set("tran prob 2", load_tran_prob_2)
      end
      extended_file = io.read()
      if extended_file == "LC3" then

        params:set("time_div_opt", tonumber(io.read()))
        selected_time_param = tonumber(io.read())
        ppqn_names = ppqn_names_variants[selected_time_param]
        ppqn_divisions = ppqn_divisions_variants[selected_time_param]
        params:set("time_div_opt", selected_time_param)
        if preset_count == 0 then
          selected_preset = 0
          sel_ppqn_div = tonumber(io.read())
          p_duration = tonumber(io.read())
        else
          for i = 1,preset_count do
            new_preset_pool[i].sel_ppqn_div = tonumber(io.read())
            new_preset_pool[i].p_duration = tonumber(io.read())
          end
          new_preset_unpack(selected_preset)
        end
        cycle_sel = tostring(io.read())
        ref_loadstate()
        params:read(_path.data .. "less_concepts_3/less_concepts-0"..selected_set)
        params:bang()
        params:set("wsyn_init",1)
      else
        --tlc for pre 2.2 saves
        sel_ppqn_div = util.round((1+#ppqn_divisions)/2)
        params:set("time_div_opt", 1)
        selected_preset = 0
        for i = 1,preset_count do
          new_preset_pool[i].sel_ppqn_div = util.round((1+#ppqn_divisions)/2) --set default clock div to centroid for old saves
          new_preset_pool[i].p_duration = 4
        end
      end
    else
      print("invalid data file")
    end
    io.close(file)
    grid_dirty = true
  else
    print("no historical save file preset, use PSETs")
  end
end

function loadstate(pset_number)
  all_loaded = false
  local file = io.open(norns.state.data.."/"..pset_number.."/script_settings.data", "r")
  if file then
    io.input(file)
    filetype = io.read()
    if filetype == "permanence" then
      preset_count = tonumber(io.read())
      if preset_count > 0 then
        selected_preset = 1
      else
        selected_preset = 0
      end
      if preset_count > 0 then
        for i = 1,preset_count do
          new_preset_pool[i].seed = tonumber(io.read())
          new_preset_pool[i].rule = tonumber(io.read())
          new_preset_pool[i].v1_bit = tonumber(io.read())
          new_preset_pool[i].v2_bit = tonumber(io.read())
          new_preset_pool[i].new_low = tonumber(io.read())
          new_preset_pool[i].new_high = tonumber(io.read())
          new_preset_pool[i].v1_octave = tonumber(io.read())
          new_preset_pool[i].v2_octave = tonumber(io.read())
        end
      else
        seed = tonumber(io.read())
        rule = tonumber(io.read())
        new_seed = seed
        new_rule = rule
        voice[1].bit = tonumber(io.read())
        voice[2].bit = tonumber(io.read())
        new_low = tonumber(io.read())
        new_high = tonumber(io.read())
        voice[1].octave = tonumber(io.read())
        voice[2].octave = tonumber(io.read())
      end
      saved_low = new_low
      saved_high = new_high
      load_bpm = tonumber(io.read())
      load_clock = tonumber(io.read())
      load_ch_1 = tonumber(io.read())
      load_ch_2 = tonumber(io.read())
      load_scale = tonumber(io.read())
      load_global_trans = tonumber(io.read())
      load_tran_1 = tonumber(io.read())
      load_tran_prob_1 = tonumber(io.read())
      load_tran_2 = tonumber(io.read())
      load_tran_prob_2 = tonumber(io.read())
      if load_bpm == nil and load_clock == nil and load_ch_1 == nil and 
      load_ch_2 == nil and load_scale == nil and load_global_trans == nil then
        --params:set("clock_tempo", 110)
        --params:set("clock_midi_out", 1)
        params:set("midi_A", 1)
        params:set("midi_B", 1)
        params:set("scale", 1)
        params:set("global transpose", 0)
      else
        --params:set("clock_tempo", load_bpm)
        --params:set("clock_midi_out", load_clock)
        params:set("midi_A", load_ch_1)
        params:set("midi_B", load_ch_2)
        params:set("scale", load_scale)
        params:set("global transpose", load_global_trans)
        params:set("transpose 1", load_tran_1)
        params:set("transpose 2", load_tran_2)
        params:set("tran prob 1", load_tran_prob_1)
        params:set("tran prob 2", load_tran_prob_2)
      end
      extended_file = io.read()
      if extended_file == "LC3" then

        params:set("time_div_opt", tonumber(io.read()))
        selected_time_param = tonumber(io.read())
        ppqn_names = ppqn_names_variants[selected_time_param]
        ppqn_divisions = ppqn_divisions_variants[selected_time_param]
        params:set("time_div_opt", selected_time_param)
        if preset_count == 0 then
          selected_preset = 0
          sel_ppqn_div = tonumber(io.read())
          p_duration = tonumber(io.read())
        else
          for i = 1,preset_count do
            new_preset_pool[i].sel_ppqn_div = tonumber(io.read())
            new_preset_pool[i].p_duration = tonumber(io.read())
          end
          new_preset_unpack(selected_preset)
        end
        cycle_sel = tostring(io.read())
        ref_loadstate()
        params:bang()
        params:set("wsyn_init",1)
      else
        --tlc for pre 2.2 saves
        sel_ppqn_div = util.round((1+#ppqn_divisions)/2)
        params:set("time_div_opt", 1)
        selected_preset = 0
        for i = 1,preset_count do
          new_preset_pool[i].sel_ppqn_div = util.round((1+#ppqn_divisions)/2) --set default clock div to centroid for old saves
          new_preset_pool[i].p_duration = 4
        end
      end
      if params:string("scale") == "olafur" then
        notes[coll] = tab.load(norns.state.data.."/"..pset_number.."/olafur_notes.data")
        if params:string("olafur_snapshot") == "on" then
          for i = 1,preset_count do
            new_preset_pool[i].olafur_notes = tab.load(norns.state.data..pset_number.."/olafur_notes"..i..".data")
          end
        end
        new_low = saved_low
        new_high = saved_high
      end
      if preset_count > 0 then
        new_preset_unpack(selected_preset)
      else
        bang()
      end
    else
      print("invalid data file")
    end
    io.close(file)
    grid_dirty = true
  end
  all_loaded = true
end

function rerun()
  norns.script.load(norns.state.script)
end
