-- bt-1O1 v0.1.0 by loopmasta
--  __          __          __
--    |        /   |        /   |
--    |       /    |       /    |
--    |      /     |      /     |
--    |     /      |     /      |
--    |    _/       |    _/       |    _
--     \/          \/          \/

engine.name = 'Bt1o1'

local STEPS = 16
local BASE_NOTE = 36  -- C2: note 0, octave 0
local LATENCY = 0.025 -- every step sounds this long after its sixteenth on the clock
local GATE = 0.5      -- gate length, in steps
local DRUM_STEPS = 16 -- the drums always loop one bar, whatever the bass length
local PAGES = {"SOUND", "SEQ", "DRUM", "MIX"} -- in K1 + E1 order
-- the rows on the DRUM page, top to bottom: the drum step's field and its label
local DRUM_ROWS = {
  {id = "kick", label = "BD"},
  {id = "hat", label = "HH"},  -- closed hat
  {id = "open", label = "OH"}, -- open hat
}

local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local SCALES = {
  {name = "minor", degrees = {0, 2, 3, 5, 7, 8, 10}},
  {name = "phrygian", degrees = {0, 1, 3, 5, 7, 8, 10}},
  {name = "dorian", degrees = {0, 2, 3, 5, 7, 9, 10}},
  {name = "min pent", degrees = {0, 3, 5, 7, 10}},
  {name = "blues", degrees = {0, 3, 5, 6, 7, 10}},
  {name = "major", degrees = {0, 2, 4, 5, 7, 9, 11}},
  {name = "harm minor", degrees = {0, 2, 3, 5, 7, 8, 11}},
  {name = "chromatic", degrees = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}},
}

-- the knobs on the SOUND page, in screen order
local KNOBS = {
  {id = "tune", label = "TUNE"},
  {id = "cutoff", label = "CUT"},
  {id = "res", label = "RES"},
  {id = "env_mod", label = "ENV"},
  {id = "decay", label = "DEC"},
  {id = "accent", label = "ACC"},
  {id = "wave", label = "WAVE"},
  {id = "drive", label = "DRV"},
}

-- the faders on the MIX page, in screen order
local FADERS = {
  {id = "volume", label = "BASS"},
  {id = "kick_level", label = "BD"},
  {id = "hat_level", label = "HH"},
  {id = "open_level", label = "OH"},
}

-- the default pattern: Josh Wink, "Higher State of Consciousness" (1995),
-- after the transcription on djjondent.blogspot.com (famous 303 bassline
-- patterns): G, G up an octave and B, every step accented.
-- {note, octave, gate, accent, slide}
local DEMO = {
  {7, 0, true, true, true}, {7, 1, true, true, false}, {7, 0, true, true, true}, {7, 0, true, true, true},
  {7, 0, true, true, false}, {7, 0, true, true, false}, {11, 0, true, true, false}, {7, 0, true, true, false},
  {11, 0, true, true, false}, {7, 0, true, true, true}, {7, 0, true, true, false}, {11, 0, true, true, false},
  {7, 0, true, true, true}, {7, 0, true, true, true}, {7, 0, true, true, false}, {11, 0, true, true, false},
}

local steps = {}
local selected = 1
local drums = {}       -- {kick = bool, hat = bool (closed), open = bool}
local drum_selected = 1
local drum_row = 1     -- picked row on DRUM (kick)
local page = 1 -- index in PAGES: starts on SOUND
local knob = 2 -- picked knob on SOUND (cutoff)
local fader = 1 -- picked fader on MIX (bass)
local k1_held = false
local ready = false -- init done: keys and encoders can come in before (the params don't exist yet)

local running = false
local seq_clock = nil
local position = 0    -- the step sent last (0 before the first)
local ticks = 0       -- sixteenths since start: the drum step is ticks % 16 + 1
local playhead = nil  -- the step shown as playing
local drum_playhead = nil
local sliding = false -- the gate was held open for a slide into the next step

local message = nil
local message_until = 0
local dirty = true
local redraw_metro

local function pattern_file() return norns.state.data .. "pattern.lua" end
local function pset_file() return norns.state.data .. "last.pset" end

local function show(text)
  message = text
  message_until = util.time() + 1.5
  dirty = true
end

local function length() return params:get("length") end

local function midi_note(step)
  return BASE_NOTE + step.note + 12 * step.octave + params:get("tune")
end

local function new_step(note, octave, gate, accent, slide)
  return {note = note, octave = octave, gate = gate, accent = accent, slide = slide}
end

local function demo_pattern()
  local pattern = {}
  for i, s in ipairs(DEMO) do pattern[i] = new_step(s[1], s[2], s[3], s[4], s[5]) end
  return pattern
end

-- default drums: kick on the beats, closed hat on the offbeats
local function demo_drums()
  local pattern = {}
  for i = 1, DRUM_STEPS do
    pattern[i] = {kick = i % 4 == 1, hat = i % 4 == 3, open = false}
  end
  return pattern
end

local function play_kick(delay)
  engine.kick(delay, params:get("kick_level") * params:get("drum_level"),
    params:get("kick_tune"), params:get("kick_decay"))
end

local function play_hat(delay, open)
  engine.hat(delay, params:get(open and "open_level" or "hat_level") * params:get("drum_level"),
    params:get(open and "hat_open_decay" or "hat_decay"))
end

-- the drum step's sounds (closed and open hat are never on the same step)
local function play_drums(delay, d)
  if d.kick then play_kick(delay) end
  if d.hat then play_hat(delay, false) end
  if d.open then play_hat(delay, true) end
end

-- sequencer ------------------------------------------------------------------

local function play_step(i, delay)
  local step = steps[i]
  if step.gate then
    engine.note(delay, midi_note(step), step.accent and 1 or 0, sliding and 1 or 0)
    local next_step = steps[i % length() + 1]
    sliding = step.slide and next_step.gate
    if not sliding then
      engine.off(delay + clock.get_beat_sec() / 4 * GATE)
    end
  elseif sliding then
    -- held for a slide, but this step was made a rest meanwhile
    engine.off(delay)
    sliding = false
  end
end

local function run()
  while true do
    clock.sync(1 / 4)
    -- how late the sync woke up: taken off the latency, so it doesn't reach the audio
    -- (from the nearest sixteenth, in case it wakes a hair early)
    local beats = clock.get_beats()
    local late = (beats - math.floor(beats * 4 + 0.5) / 4) * clock.get_beat_sec()
    local delay = math.max(0, LATENCY - late)
    -- the drums count sixteenths since start, not bass steps, so they keep
    -- the bar whatever the bass length
    local d = ticks % DRUM_STEPS + 1
    if params:get("drums") == 2 then play_drums(delay, drums[d]) end
    drum_playhead = d
    ticks = ticks + 1
    position = position % length() + 1
    play_step(position, delay)
    playhead = position
    dirty = true
  end
end

local function stop()
  if seq_clock then clock.cancel(seq_clock) end
  seq_clock = nil
  running = false
  sliding = false
  playhead = nil
  drum_playhead = nil
  engine.off(0)
  dirty = true
end

-- always from step 1, also when already running (MIDI start)
local function start()
  stop()
  position = 0
  ticks = 0
  running = true
  seq_clock = clock.run(run)
end

-- while stopped: hear the step's note once
local function preview(step)
  if running or not step.gate then return end
  engine.note(0, midi_note(step), step.accent and 1 or 0, 0)
  engine.off(0.2)
end

-- while stopped: hear the drum step's sounds
local function preview_drums(d)
  if not running then play_drums(0, d) end
end

local function randomize()
  local root = params:get("root") - 1
  local scale = SCALES[params:get("scale")]
  for i = 1, STEPS do
    local degree = math.random() < 0.35 and 0 or scale.degrees[math.random(#scale.degrees)]
    local r = math.random()
    local octave = r < 0.15 and -1 or (r < 0.3 and 1 or 0)
    steps[i] = new_step((root + degree) % 12, octave,
      math.random() < 0.8, math.random() < 0.25, math.random() < 0.2)
  end
  show("random " .. NOTE_NAMES[root + 1] .. " " .. scale.name)
end

-- saving ---------------------------------------------------------------------

local function save_pattern()
  local lines = {"-- bt-1O1 pattern", "return {"}
  for _, s in ipairs(steps) do
    table.insert(lines, string.format("  {note = %d, octave = %d, gate = %s, accent = %s, slide = %s},",
      s.note, s.octave, tostring(s.gate), tostring(s.accent), tostring(s.slide)))
  end
  table.insert(lines, "  drums = {")
  for _, d in ipairs(drums) do
    table.insert(lines, string.format("    {kick = %s, hat = %s, open = %s},",
      tostring(d.kick), tostring(d.hat), tostring(d.open)))
  end
  table.insert(lines, "  },")
  table.insert(lines, "}")

  local tmp = pattern_file() .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    print("bt-1O1: can't save the pattern")
    return
  end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  os.rename(tmp, pattern_file())
end

-- the saved pattern, or the demo; missing or broken steps are filled in.
-- returns the bass steps and the drum steps (patterns saved before the drums
-- existed get the default drums)
local function load_pattern()
  local pattern = demo_pattern()
  local drum_pattern = demo_drums()
  if util.file_exists(pattern_file()) then
    local ok, loaded = pcall(dofile, pattern_file())
    if ok and type(loaded) == "table" then
      for i = 1, STEPS do
        local s = loaded[i]
        if type(s) == "table" then
          pattern[i] = new_step(util.clamp(math.floor(tonumber(s.note) or 0), 0, 12),
            util.clamp(math.floor(tonumber(s.octave) or 0), -1, 1),
            s.gate == true, s.accent == true, s.slide == true)
        end
      end
      if type(loaded.drums) == "table" then
        for i = 1, DRUM_STEPS do
          local d = loaded.drums[i]
          if type(d) == "table" then
            if type(d.hat) == "number" then
              -- saved before the open hat had its own row: hat 0 off, 1 closed, 2 open
              drum_pattern[i] = {kick = d.kick == true, hat = d.hat == 1, open = d.hat == 2}
            else
              drum_pattern[i] = {kick = d.kick == true, hat = d.hat == true, open = d.open == true and d.hat ~= true}
            end
          end
        end
      end
    else
      print("bt-1O1: can't load the pattern: " .. tostring(loaded))
    end
  end
  return pattern, drum_pattern
end

-- params ---------------------------------------------------------------------

local function fmt_percent(p) return math.floor(p:get() * 100 + 0.5) .. "%" end

local function fmt_hz(p)
  local x = p:get()
  if x >= 1000 then return string.format("%.1f kHz", x / 1000) end
  return math.floor(x + 0.5) .. " Hz"
end

local function fmt_seconds(p)
  local x = p:get()
  if x < 1 then return math.floor(x * 1000 + 0.5) .. " ms" end
  return string.format("%.2f s", x)
end

local function fmt_tune(p)
  local x = p:get()
  return string.format("%s%.1f st", x > 0 and "+" or "", x)
end

local function add_params()
  params:add_separator("bt1o1", "bt-1O1")

  params:add_group("bt1o1_sound", "SOUND", 9)

  params:add_control("tune", "tune", controlspec.new(-12, 12, "lin", 0.1, 0, "", 1 / 240), fmt_tune)
  params:set_action("tune", function() dirty = true end) -- applies from the next note

  local function add(id, name, spec, formatter)
    params:add_control(id, name, spec, formatter)
    params:set_action(id, function(x) engine[id](x); dirty = true end)
  end

  add("cutoff", "cutoff", controlspec.new(40, 8000, "exp", 0, 400, "Hz"), fmt_hz)
  add("res", "resonance", controlspec.new(0, 1, "lin", 0, 0.6, ""), fmt_percent)
  add("env_mod", "env mod", controlspec.new(0, 1, "lin", 0, 0.5, ""), fmt_percent)
  add("decay", "decay", controlspec.new(0.2, 2.5, "exp", 0, 0.5, "s"), fmt_seconds)
  add("accent", "accent", controlspec.new(0, 1, "lin", 0, 0.6, ""), fmt_percent)

  params:add_option("wave", "wave", {"saw", "square"}, 1)
  params:set_action("wave", function(x) engine.wave(x - 1); dirty = true end)

  add("drive", "drive", controlspec.new(0, 1, "lin", 0, 0.2, ""), fmt_percent)
  add("volume", "bass level", controlspec.new(0, 1, "lin", 0, 0.6, ""), fmt_percent)

  params:add_group("bt1o1_seq", "SEQUENCER", 3)
  params:add_number("length", "length", 1, STEPS, STEPS)
  params:set_action("length", function() dirty = true end)
  params:add_option("root", "root", NOTE_NAMES, 1)
  local scale_names = {}
  for i, s in ipairs(SCALES) do scale_names[i] = s.name end
  params:add_option("scale", "scale", scale_names, 1)

  params:add_group("bt1o1_drums", "DRUMS", 9)
  params:add_option("drums", "drums", {"off", "on"}, 2)
  params:add_control("drum_level", "drums level", controlspec.new(0, 1, "lin", 0, 1, ""), fmt_percent)
  params:add_control("kick_level", "kick level", controlspec.new(0, 1, "lin", 0, 0.6, ""), fmt_percent)
  params:add_control("kick_tune", "kick tune", controlspec.new(30, 100, "exp", 0, 50, "Hz"), fmt_hz)
  params:add_control("kick_decay", "kick decay", controlspec.new(0.1, 1.5, "exp", 0, 0.4, "s"), fmt_seconds)
  params:add_control("hat_level", "closed level", controlspec.new(0, 1, "lin", 0, 0.5, ""), fmt_percent)
  params:add_control("open_level", "open level", controlspec.new(0, 1, "lin", 0, 0.5, ""), fmt_percent)
  params:add_control("hat_decay", "closed decay", controlspec.new(0.02, 0.3, "exp", 0, 0.06, "s"), fmt_seconds)
  params:add_control("hat_open_decay", "open decay", controlspec.new(0.1, 1.5, "exp", 0, 0.5, "s"), fmt_seconds)
  for _, id in ipairs({"drums", "drum_level", "kick_level", "hat_level", "open_level"}) do
    params:set_action(id, function() dirty = true end)
  end
end

-- norns -----------------------------------------------------------------------

function init()
  steps, drums = load_pattern()
  add_params()
  if util.file_exists(pset_file()) then params:read(pset_file()) end
  params:bang()

  -- MIDI start / stop (with PARAMETERS > CLOCK > source = midi)
  clock.transport.start = start
  clock.transport.stop = stop

  redraw_metro = metro.init(function()
    if message and util.time() > message_until then
      message = nil
      dirty = true
    end
    if dirty then
      redraw()
      dirty = false
    end
  end, 1 / 30)
  redraw_metro:start()
  ready = true
end

function key(n, z)
  if not ready then return end
  -- norns only sends K1 to the script once it's held (0.25 s)
  if n == 1 then
    k1_held = (z == 1)
    dirty = true
    return
  end
  if z == 0 then return end

  local step = steps[selected]
  local name = PAGES[page]
  if n == 3 and not k1_held then
    if running then stop() else start() end
  elseif name == "SEQ" then
    if n == 2 and not k1_held then
      step.accent = not step.accent
    elseif n == 2 then
      step.slide = not step.slide
    elseif n == 3 then
      step.gate = not step.gate
      preview(step)
    end
  elseif name == "DRUM" then
    if n == 2 and not k1_held then
      local d = drums[drum_selected]
      local id = DRUM_ROWS[drum_row].id
      d[id] = not d[id]
      -- one hat per step: an open hat would be cut by the closed one anyway
      if id == "hat" and d.hat then d.open = false end
      if id == "open" and d.open then d.hat = false end
      if d[id] then preview_drums({[id] = true}) end
    end
  elseif name == "MIX" then
    -- nothing on K2 yet
  elseif n == 2 and k1_held then -- SOUND
    randomize()
  elseif n == 2 then
    params:set("drums", params:get("drums") == 2 and 1 or 2)
    show("drums " .. params:string("drums"))
  end
  dirty = true
end

function enc(n, d)
  if not ready then return end
  local name = PAGES[page]
  if n == 1 and k1_held then
    page = util.clamp(page + d, 1, #PAGES)
  elseif name == "SEQ" then
    local step = steps[selected]
    if n == 1 then
      selected = util.clamp(selected + d, 1, STEPS)
    elseif n == 3 and k1_held then
      params:delta("length", d)
      show("length " .. length())
    elseif n == 2 and not k1_held then
      step.note = util.clamp(step.note + d, 0, 12)
      step.gate = true
      preview(step)
    elseif n == 3 then
      step.octave = util.clamp(step.octave + d, -1, 1)
      step.gate = true
      preview(step)
    end
  elseif name == "DRUM" then
    if n == 1 then
      drum_selected = util.clamp(drum_selected + d, 1, DRUM_STEPS)
    elseif n == 2 and not k1_held then
      drum_row = util.clamp(drum_row + d, 1, #DRUM_ROWS)
    end
  elseif name == "MIX" then
    if n == 2 and not k1_held then
      fader = util.clamp(fader + d, 1, #FADERS)
    elseif n == 3 and not k1_held then
      params:delta(FADERS[fader].id, d)
    end
  elseif not k1_held then -- SOUND
    if n == 2 then
      knob = util.clamp(knob + d, 1, #KNOBS)
    elseif n == 3 then
      params:delta(KNOBS[knob].id, d)
    end
  end
  dirty = true
end

-- screen -----------------------------------------------------------------------

local function note_name(step)
  if step.note == 12 then return "C'" end
  return NOTE_NAMES[step.note + 1]
end

-- top line: what's edited (or a message) on the left, the page on the right
local function draw_top(text)
  screen.level(15)
  screen.move(0, 6)
  screen.text(message or text)
  screen.level(k1_held and 15 or 3)
  screen.move(128, 6)
  screen.text_right(PAGES[page])
end

-- 16 boxes at the bottom: length, beats and the playing step
-- (the bass pattern's, or with `drum` the drum pattern's)
local function draw_strip(drum)
  local head = drum and drum_playhead or playhead
  local len = drum and DRUM_STEPS or length()
  for i = 1, STEPS do
    local level
    if i == head then level = 15
    elseif i > len then level = 1
    elseif i % 4 == 1 then level = 5
    else level = 3 end
    screen.level(level)
    screen.rect((i - 1) * 8 + 1, 59, 6, 4)
    screen.fill()
  end
end

-- the selected step: a bright bar under its column, above the strip. not a dim
-- column behind the notes: on the OLED, rows with many bright pixels darken
-- the dim pixels next to them, which showed as dark lines across the column
local function draw_marker(i)
  screen.level(15)
  screen.rect((i - 1) * 8 + 1, 54, 6, 2)
  screen.fill()
end

-- y of a step's note in the piano roll: one pixel per semitone, C1 at the bottom
local function note_y(step)
  return 50 - (step.note + 12 * step.octave + 12)
end

local function draw_seq()
  local step = steps[selected]
  local text = string.format("%02d ", selected)
  if step.gate then
    text = text .. note_name(step)
      .. (step.octave == 1 and " up" or (step.octave == -1 and " dn" or ""))
      .. (step.accent and " acc" or "") .. (step.slide and " sld" or "")
  else
    text = text .. "rest"
  end
  draw_top(text)
  draw_marker(selected)

  for i = 1, STEPS do
    local s = steps[i]
    if s.gate then
      local x = (i - 1) * 8 + 1
      local y = note_y(s)
      local level = s.accent and 15 or 7
      if i > length() then level = 2 end
      screen.level(level)
      screen.rect(x, y, 6, 2)
      screen.fill()
      local n = steps[i % STEPS + 1]
      if s.slide and n.gate and i < STEPS then
        screen.move(x + 6, y + 1)
        screen.line(x + 8, note_y(n) + 1)
        screen.stroke()
      end
    end
  end
  draw_strip()
end

local function draw_sound()
  local p = params:lookup_param(KNOBS[knob].id)
  draw_top(p.name .. " " .. p:string())

  for i, k in ipairs(KNOBS) do
    local x = ((i - 1) % 4) * 32
    local y = i <= 4 and 12 or 35
    local level = i == knob and 15 or 4
    screen.level(level)
    screen.move(x + 1, y + 6)
    screen.text(k.label)
    -- the value as a bar, 0..1 of the param's range
    local raw = k.id == "wave" and (params:get("wave") - 1) or params:get_raw(k.id)
    screen.level(i == knob and 3 or 1)
    screen.rect(x + 1, y + 10, 28, 4)
    screen.fill()
    screen.level(level)
    screen.rect(x + 1, y + 10, math.max(1, math.floor(raw * 28 + 0.5)), 4)
    screen.fill()
  end
  draw_strip()
end

local function draw_drum()
  local row = DRUM_ROWS[drum_row]
  local text = string.format("%02d %s %s", drum_selected, row.label,
    drums[drum_selected][row.id] and "on" or "off")
  if params:get("drums") == 1 then text = text .. "  (muted)" end
  draw_top(text)

  -- the selected step in the picked row: a bright bar right under it
  -- (no dim bands, see draw_marker)
  local function row_y(r) return (r - 1) * 15 + 10 end
  screen.level(15)
  screen.rect((drum_selected - 1) * 8 + 1, row_y(drum_row) + 12, 6, 2)
  screen.fill()

  -- one row per sound: a block for a hit, a dim dash (brighter on the beats) for none
  for r, dr in ipairs(DRUM_ROWS) do
    local y = row_y(r)
    for i = 1, DRUM_STEPS do
      local x = (i - 1) * 8 + 1
      if drums[i][dr.id] then
        screen.level(r == drum_row and 15 or 10)
        screen.rect(x, y + 1, 6, 10)
      else
        screen.level(i % 4 == 1 and 4 or 2)
        screen.rect(x, y + 5, 6, 2)
      end
      screen.fill()
    end
  end

  draw_strip(true)
end

-- text centered on x, on a whole pixel: text_center can land on a half pixel,
-- which blurs the font
local function text_center(x, y, text)
  local w = screen.text_extents(text)
  screen.move(x - math.floor(w / 2), y)
  screen.text(text)
end

-- vertical faders, the value above and the label under each, the picked one bright
local function draw_mix()
  local p = params:lookup_param(FADERS[fader].id)
  draw_top(p.name .. " " .. p:string() .. (params:get("drums") == 1 and "  (muted)" or ""))

  for i, f in ipairs(FADERS) do
    local x = (i - 1) * 32 + 16 -- the fader's center
    local raw = params:get_raw(f.id)
    local h = math.max(1, math.floor(raw * 28 + 0.5))
    local level = i == fader and 15 or 4
    screen.level(level)
    text_center(x, 15, tostring(math.floor(params:get(f.id) * 100 + 0.5)))
    screen.level(i == fader and 3 or 1)
    screen.rect(x - 4, 18, 8, 28)
    screen.fill()
    screen.level(level)
    screen.rect(x - 4, 46 - h, 8, h)
    screen.fill()
    screen.level(level)
    text_center(x, 55, f.label)
  end
  draw_strip()
end

function redraw()
  if not ready then return end
  screen.clear()
  local name = PAGES[page]
  if name == "SOUND" then draw_sound()
  elseif name == "SEQ" then draw_seq()
  elseif name == "DRUM" then draw_drum()
  else draw_mix() end
  screen.update()
end

function cleanup()
  -- norns cancels the clock routines and clears clock.transport itself
  params:write(pset_file())
  save_pattern()
end
