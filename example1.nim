##
##  Mirror an input midi port to two output ports, but make the
##  second output port's notes half the velocity and one octave lower
##

import midi
from os import sleep

# so that we can raise an exception on Ctrl-C
type EKeyboardInterrupt = object of CatchableError
proc handler() {.noconv.} =
  raise newException(EKeyboardInterrupt, "Keyboard Interrupt")
setControlCHook(handler)

midiInit("test")

let in1 = createMidiPort("in1", Input)
let out1 = createMidiPort("out1", Output)
let out2 = createMidiPort("out2", Output)

# forward in1 to both out1 and out2
in1.forwardTo(@[out1, out2])

# on out2, drop notes two octaves
out2.setCallback(
  proc(p: MidiPort, msg: var MidiMsg) =
    if msg.len == 3 and msg[0] >= 0x80 and msg[0] <= 0x9f:
      if msg[1] > 24:
        msg[1] = msg[1] - 24
      msg[2] = msg[2] div 2
)

#in1.connect("Midi-Bridge:LinnStrument MIDI 3:(capture_0) LinnStrument MIDI MIDI 1")
#out1.connect("Pianoteq:midi_in")

# it seems more reliable to call midiActivate after creating & connecting ports
midiActivate()

echo "Press CTRL-C to quit."
try:
  while true:
    sleep(1000)
except CatchableError:
  echo "\r\nShutting down..."
  midiShutdown()
  os.sleep(150)
