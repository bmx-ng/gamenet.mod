SuperStrict

Framework BRL.StandardIO
Import GameNet.Replay

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(TReplayTape.Create(0, 4, 8, 2) = Null, "reject zero players")
Check(TReplayTape.Create(2, 0, 8, 2) = Null, "reject zero capacity")
Check(TReplayTape.Create(2, 4, 0, 2) = Null, "reject zero state size")
Check(TReplayTape.Create(2, 4, 8, 65536) = Null, "reject input beyond wire length")

Local tape:TReplayTape = TReplayTape.Create(2, 4, 8, 2)
Local initialState:Byte[4]
initialState[0] = 10
initialState[1] = 20
initialState[2] = 30
initialState[3] = 40
Check(tape.Begin(100, Byte Ptr(initialState), Size_T(initialState.Length)), "begin replay")

Local input0:Byte[2]
Local input1:Byte[2]
Local inputs:SPacketView[2]
For Local offset:Int = 0 Until 4
	input0[0] = Byte(offset)
	input0[1] = Byte(offset + 1)
	input1[0] = Byte(10 + offset)
	input1[1] = Byte(20 + offset)
	inputs[0] = New SPacketView(Byte Ptr(input0), 2)
	inputs[1] = New SPacketView(Byte Ptr(input1), 2)
	Check(tape.Append(UInt(100 + offset), inputs, $1000:UInt + UInt(offset), offset Mod 2 = 0), "append replay frame")
Next
Check(Not tape.Append(104, inputs), "bounded tape rejects overflow")
Check(tape.FrameCount() = 4 And tape.InitialFrame() = 100, "replay counts")

Local restoredState:SPacketView
Check(tape.InitialState(restoredState) And restoredState.Length() = 4 And restoredState.Data()[2] = 30, "read initial state")
Local frame:SReplayFrame
Check(tape.GetFrame(2, frame) And frame.Frame() = 102 And frame.HasStateHash() And frame.StateHash() = $1002, "read indexed replay frame")
Local payload:SPacketView
Check(frame.Input(1, payload) And payload.Length() = 2 And payload.Data()[0] = 12 And payload.Data()[1] = 22, "read replay input")

Local cursor:SReplayCursor = tape.Cursor()
Local visited:Int
While cursor.Next(frame)
	Check(frame.Frame() = 100 + UInt(visited), "cursor frame order")
	visited :+ 1
Wend
Check(visited = 4 And cursor.Remaining() = 0, "cursor visits every frame")
cursor.Reset()
Check(cursor.Position() = 0 And cursor.Remaining() = 4, "reset cursor")

Local encoded:Byte[256]
Local encodedLength:Size_T = tape.Write(Byte Ptr(encoded), Size_T(encoded.Length))
Check(encodedLength = tape.SerializedSize() And encodedLength > 0, "serialize replay")
Check(tape.Write(Byte Ptr(encoded), encodedLength - 1) = 0, "reject short serialization buffer")

Local loaded:TReplayTape = TReplayTape.Create(2, 4, 8, 2)
Check(loaded.Read(New SPacketView(Byte Ptr(encoded), encodedLength)), "load serialized replay")
Check(loaded.FrameCount() = 4 And loaded.InitialFrame() = 100, "loaded replay counts")
Check(loaded.GetFrame(3, frame) And frame.Frame() = 103 And Not frame.HasStateHash(), "loaded hash validity")
Check(frame.Input(0, payload) And payload.Data()[0] = 3 And payload.Data()[1] = 4, "loaded replay input")

' Loading is atomic: corrupt data is rejected and the existing tape survives.
encoded[0] :~ 1
Check(Not loaded.Read(New SPacketView(Byte Ptr(encoded), encodedLength)), "reject corrupt replay magic")
Check(loaded.FrameCount() = 4 And loaded.GetFrame(3, frame) And frame.Frame() = 103, "invalid load preserves recording")
encoded[0] :~ 1
Local firstInputLengthOffset:Int = 18 + initialState.Length + 9
Local savedLengthByte:Byte = encoded[firstInputLengthOffset]
encoded[firstInputLengthOffset] = 1
Check(Not loaded.Read(New SPacketView(Byte Ptr(encoded), encodedLength)), "reject oversized encoded input")
Check(loaded.FrameCount() = 4 And loaded.GetFrame(3, frame) And frame.Frame() = 103, "invalid length preserves recording")
encoded[firstInputLengthOffset] = savedLengthByte
encoded[Int(encodedLength) - 5] :~ 1
Check(Not loaded.Read(New SPacketView(Byte Ptr(encoded), encodedLength)), "reject replay payload checksum mismatch")
Check(loaded.FrameCount() = 4 And loaded.GetFrame(3, frame) And frame.Frame() = 103, "checksum failure preserves recording")

Print "GameNet.Replay tests passed"
