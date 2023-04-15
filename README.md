# Nim & Jack Audio for MIDI fun

Jack's API can be a little fiddly.  jackmidi.nim provides a simple wrapper
focused on midi input and output, helping you to manage multiple input and
output ports.

You can attach a callback to each port, which can read or modify any messages
coming through.

# Examples

## `example1.nim`

`example1.nim` creates a jack client with one midi input (in1) and two midi
outputs (out1, out2).

It will copy all inputs from in1 to both out1 and out2, but will drop
noteOn/noteOff messages by two octaves on out2.

## `example2_linnstrument.nim`

This will put the Linnstrument midi controller into User Firmware Mode and will
parse all the incoming events, echoing them to stdout.

You probably have to change the connect() port names.
