import jack/jack, jack/types, jack/midiport
import std/rlocks
from os import sleep

type
  MidiMsg* = seq[uint8]

  PortType* = enum
    Input
    Output
  MidiPortCallback* = proc(port: MidiPort, midiMsg: var MidiMsg)
  MidiPort* = ref object
    portID*: int
    portType*: PortType
    name*: string
    jackPort: ptr JackPort
    outQueue*: seq[MidiMsg]
    callback: MidiPortCallback

var
  midiPorts: seq[MidiPort]
  client: ptr JackClient
  clientName: string
  lock: RLock
  sampleRate: int
  bufferSize: int

proc getMidiPorts*(): seq[MidiPort] = midiPorts
proc getSampleRate*(): int = sampleRate
proc getBufferSize*(): int = bufferSize

proc createMidiPort*(name: string, portType: PortType): MidiPort =
  for port in midiPorts:
    if name == port.name:
      debugEcho "Attempted to create a port with the same name as an existing port"
      return nil
  case portType
  of Input:
    var jport = jack_port_register(client, name.cstring, JACK_DEFAULT_MIDI_TYPE, culong(JackPortIsInput), 0)
    var port = MidiPort(name: name, portType: Input, jackPort: jport)
    midiPorts.add(port)
    return port
  of Output:
    var jport = jack_port_register(client, name.cstring, JACK_DEFAULT_MIDI_TYPE, culong(JackPortIsOutput), 0)
    var port = MidiPort(name: name, portType: Output, jackPort: jport, outQueue: newSeqOfCap[MidiMsg](32))
    midiPorts.add(port)
    return port

proc connect*(p: MidiPort, otherPort: string) =
  let portName = jack_port_name(p.jackPort)
  case p.portType
  of Input:
    discard jack_connect(client, otherPort, portName)
  of Output:
    discard jack_connect(client, portName, otherPort)

proc disconnect*(p: MidiPort, otherPort: string) =
  let portName = jack_port_name(p.jackPort)
  discard jack_disconnect(client, portName, otherPort)

proc disconnect*(p: MidiPort) =
  discard jack_port_disconnect(client, p.jackPort)

## callbacks will be run either on receiving or before sending messages
## To stop a midimsg from being sent in an output port's callback,
## call midimsg.setLen(0)
proc setCallback*(p: MidiPort, cb: MidiPortCallback) =
  acquire(lock)
  defer: release(lock)
  p.callback = cb

## send will send the given midi message at the next available opportunity
## Note: there is some timing granularity lost with this wrapper around
## jack's implementation, as jack supports per-sample accuracy within each
## buffer, which we currently ignore.
proc send*(p: MidiPort, msg: var MidiMsg) =
  if p.portType != Output or len(msg) == 0:
    return
  lock.acquire()
  defer: lock.release()
  if p.callback != nil:
    p.callback(p, msg)
  if len(msg) != 0:
    p.outQueue.add(msg)

## forwardTo sets the callback to forward all messages to the given output ports
proc forwardTo*(inport: MidiPort, outports: seq[MidiPort]) =
  if inport.portType != Input:
    return
  for outport in outports:
    if outport.portType != Output:
      return
  setCallback(inport,
    proc(p: MidiPort, msg: var MidiMsg) =
      for outport in outports:
        var msgcopy = msg
        outport.send(msgcopy)
  )

proc jack_sample_rate_cb(nframes: jack_nframes, arg: pointer): cint =
  sampleRate = int(nframes)

proc jack_buffer_size_cb(nframes: jack_nframes, arg: pointer): cint =
  bufferSize = int(nframes)

proc real_jack_process_cb(nframes: jack_nframes, arg: pointer): cint =
  # process input ports
  for port in midiPorts:
    if port.portType != Input or port.callback == nil:
      continue
    let midiInBuf = jack_port_get_buffer(port.jackPort, nframes)
    var midiEventCount = jack_midi_get_event_count(midiInBuf)
    for i in 0..<midiEventCount:
      var event: JackMidiEvent
      discard jack_midi_event_get(event.addr, midiInBuf, uint32(i))
      var msg: MidiMsg = newSeq[uint8](event.size)
      copyMem(msg[0].addr, event.buffer, event.size)
      try:
        port.callback(port, msg)
      except CatchableError as e:
        echo "Exception ", type(e[]), ": ", e.msg
        echo e.getStackTrace()

  # process output ports
  for port in midiPorts:
    if port.portType != Output:
      continue
    var midiOutBuf = jack_port_get_buffer(port.jackPort, nframes)
    jack_midi_clear_buffer(midiOutBuf)
    var i: jack_nframes = 0
    var clearQueue = true
    for idx, msg in port.outQueue:
      if len(msg) == 0:
        continue
      if 0 != jack_midi_event_write(midiOutBuf, i, cast[ptr JackMidiData](msg[0].unsafeAddr), csize_t(msg.len)):
        clearQueue = false
        break
      port.outQueue[idx].setLen(0)  # ensure it won't be sent again
      inc i
      if i > nframes:
        clearQueue = false
        break
    if clearQueue:  # all messages were successfully sent, so start from 0 again
      port.outQueue.setLen(0)

## jack_process_cb will be called by jack during its realtime loop.
## It is a simple wrapper for real_jack_process_cb.
## We catch & print any exceptions here, or bad things happen and exceptions get swallowed.
proc jack_process_cb(nframes: jack_nframes, arg: pointer): cint =
  try:
    acquire(lock)
    return real_jack_process_cb(nframes, arg)
  except Exception as e:
    echo "Exception ", type(e[]), ": ", e.msg
    echo e.getStackTrace()
  finally:
    release(lock)

## call midiInit to initialize the midi subsystem, passing in your preferred name for the client
proc midiInit*(name: string) =
  var status: JackStatus
  var options: Jack_options
  clientName = name
  client = jack_client_open(clientName.cstring, options, status.addr)
  if status != 0:
    echo "Failed to create jack client"
    quit(1)
  if 0 != jack_set_process_callback(client, JackProcessCallback(jack_process_cb), nil):
    echo "Failed to configure jack process callback"
    quit(1)
  if 0 != jack_set_sample_rate_callback(client, JackSampleRateCallback(jack_sample_rate_cb), nil):
    echo "Failed to configure jack sample rate callback"
    quit(1)
  if 0 != jack_set_buffer_size_callback(client, JackBufferSizeCallback(jack_buffer_size_cb), nil):
    echo "Failed to configure jack buffer size callback"
    quit(1)
  discard jack_set_buffer_size(client, jacknframes(1024))

proc midiActivate*() =
  if 0 != jack_activate(client):
    echo "Failed to activate jack client"
    quit(1)

proc midiShutdown*() =
  for port in midiPorts:
    port.disconnect()
    os.sleep(25)
  discard jack_deactivate(client)
  os.sleep(25)
  discard jack_client_close(client)
  os.sleep(25)

block moduleInit:
  initRLock(lock)
  midiPorts = newSeqOfCap[MidiPort](8)
