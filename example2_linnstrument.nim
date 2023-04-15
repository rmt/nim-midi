##
##  Mirror an input midi port to two output ports, but make the
##  second output port's notes half the velocity and one octave lower
##

import math
from os import sleep

import midi

type
  Color {. pure, size:1 .} = enum   # reluctantly misspelled
    Default = 0'u8
    Red = 1'u8
    Yellow = 2'u8
    Green = 3'u8
    Cyan = 4'u8
    Blue = 5'u8
    Magenta = 6'u8
    Off = 7'u8
    White = 8'u8
    Orange = 9'u8
    Lime = 10'u8
    Pink = 11'u8

  NoteType {. size: 1 .} = enum
    OFF   # not part of key
    KEY   # part of key
    ROOT  # root note of key

  Linnstrument = object
    rootOffset: uint8  # C is 0, B is 11
    startNote: uint8  # eg. 30
    rowOffset: uint8  # eg. 5
    key: seq[NoteType]
    offColor: Color
    rootColor: Color
    keyColor: Color
    pressedColor: Color

const
  MAJOR_KEY = @[ROOT,OFF,KEY,OFF,KEY,KEY,OFF,KEY,OFF,KEY,OFF,KEY]
  MINOR_KEY = @[ROOT,OFF,KEY,KEY,OFF,KEY,OFF,KEY,KEY,OFF,OFF,KEY]
  KEY_C = 0'u8
  KEY_CSHARP = 1'u8
  KEY_D = 2'u8
  KEY_DSHARP = 3'u8
  KEY_E = 4'u8
  KEY_F = 5'u8
  KEY_FSHARP = 6'u8
  KEY_G = 7'u8
  KEY_GSHARP = 8'u8
  KEY_A = 9'u8
  KEY_ASHARP = 10'u8
  KEY_B = 11'u8

var LS = Linnstrument(
  startNote: 30'u8,
  rootOffset: KEY_FSHARP,
  rowOffset: 5'u8,
  key: MINOR_KEY,
  offColor: Color.Off,
  rootColor: Color.Blue,
  keyColor: Color.White,
  pressedColor: Color.Red,
)

midiInit("LinnstrumentUserMode")
let lsIn = createMidiPort("ls_in", Input)
let lsOut = createMidiPort("ls_out", Output)
let midiOut = createMidiPort("midi_out", Output)

proc sendCC(p: MidiPort; channel, cc, value: uint8) =
  if channel > 15 or cc > 127 or value > 127:
    echo "sendCC('", p.name, "', ", channel, ", ", cc, ", ", value, ") invalid"
    return
  var msg = MidiMsg(@[176'u8 + channel, cc, value])
  p.send(msg)

proc sendPB(p: MidiPort; channel: uint8; value: int) =
  if channel > 15 or value < 0 or value > 2^14:
    echo "sendPB('", p.name, "', ", channel, ", ", value, ") invalid"
    return
  var msg = MidiMsg(@[14+channel, uint8(value shr 7) and 0x7f'u8, uint8(value and 0x7f)])
  p.send(msg)

proc sendNRPN(p: MidiPort; channel: uint8 = 1; nrpn, value: int) =
  assert channel < 16
  assert nrpn >= 0 and nrpn < 2^14
  assert value >= 0 and value < 2^14
  sendCC(p, channel, 99, uint8(nrpn shr 7) and 0x7f'u8)
  sendCC(p, channel, 98, uint8(nrpn and 0x7f))
  sendCC(p, channel, 6, uint8(value shr 7) and 0x7f'u8)
  sendCC(p, channel, 38, uint8(value and 0x7f))
  sendCC(p, channel, 101, 0x7f)
  sendCC(p, channel, 100, 0x7f)

proc setRowCC(cc: uint8, row: uint8, enable: bool) =
  if row < 8:
    lsOut.sendCC(row, cc, if enable: 1'u8 else: 0'u8)
  else:
    for row in 0'u8..7'u8:
      lsOut.sendCC(row, cc, if enable: 1'u8 else: 0'u8)
proc setRowSlide(row: uint8, enable: bool) = setRowCC(9'u8, row, enable)
proc setRowX(row: uint8, enable: bool) = setRowCC(10'u8, row, enable)
proc setRowY(row: uint8, enable: bool) = setRowCC(11'u8, row, enable)
proc setRowZ(row: uint8, enable: bool) = setRowCC(12'u8, row, enable)

var colTrack: array[8*26, Color]
proc setColor(column, row: uint8, color: Color) =
  if column > 26 or row > 7:
    return
  let idx = row*26 + column
  if colTrack[idx] == color:
    return
  lsOut.sendCC(1, 20'u8, column)
  lsOut.sendCC(1, 21'u8, row)
  lsOut.sendCC(1, 22'u8, uint8(color))

proc getNoteType(note: uint8): NoteType {.inline.} =
  return LS.key[(note - LS.rootOffset) mod 12]

proc getMidiNote(column: uint8, row: uint8): uint8 {.inline.} =
  return LS.startNote + (row * LS.rowOffset) + column - 1

proc resetColor(column, row: uint8) =
  if column == 0:
    setColor(column, row, LS.rootColor)
    return

  let note = getMidiNote(column, row)
  let nt = getNoteType(note)
  case nt
  of OFF: setColor(column, row, LS.offColor)
  of ROOT: setColor(column, row, LS.rootColor)
  of KEY: setColor(column, row, LS.keyColor)

proc initColors() =
  echo "Setting left hand button colours"
  for row in 0'u8..7'u8:
    setColor(0, row, Color.Lime)
  sleep(4)

  echo "Setting note colours"
  for row in 0'u8..7'u8:
    for column in 1'u8..25'u8:
      resetColor(column, row)
    sleep(24)

#
# Ok, now we add our logic
#
proc myInit() =
  lsIn.connect("Midi-Bridge:LinnStrument MIDI 3:(capture_0) LinnStrument MIDI MIDI 1")
  lsOut.connect("Midi-Bridge:LinnStrument MIDI 3:(playback_0) LinnStrument MIDI MIDI 1")
  midiOut.connect("Pianoteq:midi_in")

  sleep(75)
  echo "Sending NRPN 245=1 to Linnstrument to switch to user firmware mode"
  lsOut.sendNRPN(1, 245, 1)
  sleep(250)
  initColors()
  setRowX(255, true)
  setRowSlide(255, true)
  setRowY(255, true)
  setRowZ(255, true)

proc myShutdown() =
  lsOut.sendNRPN(1, 245, 0)  # turn off user firmware mode
  sleep(75)

### handle input from linnstrument in user firmware mode
var XMSB: array[8*26, uint8]  # most significant bit of X
proc ls_input(p: MidiPort, msg: var MidiMsg) =
  if len(msg) != 3:
    echo msg
    return

  let msgType = msg[0] and 0xf0'u8
  let channel = msg[0] and 0x0f'u8

  # if it's just a noteOn/noteOff, adjust note and send it
  case msgType
  of 0x80'u8, 0x90'u8:
    let column = msg[1]
    let row = channel
    msg[1] = getMidiNote(column, row)
    midiOut.send(msg)
    if msg[0] <= 0x8f:
      resetColor(column, row)
    else:
      setColor(column, row, LS.pressedColor)
    return
  of 0xB0'u8:
    let row = channel
    let cc = msg[1]
    if cc <= 25 and row < 8:  # MSB of X position
      let column = cc
      XMSB[row*26 + column] = msg[2]
    elif cc >= 32 and cc <= 57 and row < 8:  # LSB of X position
      let column = cc - 32
      let msb = XMSB[row*26 + column]  # MSB is always sent first by linnstrument
      let xpos = int(msg[2]) + (int(msb) shl 7)
      let note = getMidiNote(column, row)
      echo msg, " :: ", column, ",", row, " -> ", note, " = ", xpos
      # TODO: figure out X relative to center of starting key (cellwidth = 4265 / 25.0)
    elif cc >= 64 and cc <= 89 and row < 8:
      let column = cc - 64
      let ypos = msg[2]
      let note = getMidiNote(column, row=channel)
      echo "YPosition for ", note, " is ", ypos
    elif cc == 119:
      echo "Slide: ", msg
  of 0xA0'u8:  # polyphonic aftertouch/pressure
    msg[1] = getMidiNote(column=msg[1], row=channel)
    midiOut.send(msg)
  else:
    echo msg

when isMainModule:
  var running = true
  proc handler() {.noconv.} =
    running = false
  setControlCHook(handler)

  echo "Press CTRL-C to quit."
  try:
    midiActivate()
    sleep(125)
    myInit()
    lsIn.setCallback(ls_input)
    while running:
      sleep(125)
  finally:
    echo "\nShutting down..."
    myShutdown()
    midiShutdown()
  sleep(125)
