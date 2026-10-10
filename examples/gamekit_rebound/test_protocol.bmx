SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSession

Include "protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local packet:Byte[16]
Local length:Size_T = EncodeReboundInput(Byte Ptr(packet), Size_T(packet.Length), -83, True)
Local movement:Int
Local power:Int
Check(length = REBOUND_INPUT_SIZE, "input size")
Check(DecodeReboundInput(New SPacketView(Byte Ptr(packet), length), movement, power), "decode input")
Check(movement = -83 And power, "input values")

Local seed:UInt = $12345678:UInt

Local first:TReboundSimulation = New TReboundSimulation
Local second:TReboundSimulation = New TReboundSimulation
first.Reset(seed)
second.Reset(seed)

Local player0Input:Byte[2]
Local player1Input:Byte[2]
Local inputs:SRollbackInput[2]
Local firstState:Byte[REBOUND_STATE_SIZE]
Local secondState:Byte[REBOUND_STATE_SIZE]
Local sawPoint:Int

For Local frame:UInt = 0 Until 1200
	Local axis0:Int = -127
	Local axis1:Int = 127
	If (frame / 120) Mod 2 Then axis0 = 127; axis1 = -127
	EncodeReboundInput(Byte Ptr(player0Input), Size_T(player0Input.Length), axis0, frame Mod 90 < 12)
	EncodeReboundInput(Byte Ptr(player1Input), Size_T(player1Input.Length), axis1, frame Mod 110 < 12)
	inputs[0] = New SRollbackInput(frame, 0, ERollbackInputStatus.Confirmed, New SPacketView(Byte Ptr(player0Input), REBOUND_INPUT_SIZE))
	inputs[1] = New SRollbackInput(frame, 1, ERollbackInputStatus.Confirmed, New SPacketView(Byte Ptr(player1Input), REBOUND_INPUT_SIZE))
	Check(first.SimulateFrame(frame, inputs), "first simulation")
	Check(second.SimulateFrame(frame, inputs), "second simulation")
	Local firstLength:Size_T = first.SaveState(Byte Ptr(firstState), Size_T(firstState.Length))
	Local secondLength:Size_T = second.SaveState(Byte Ptr(secondState), Size_T(secondState.Length))
	Check(firstLength = REBOUND_STATE_SIZE And secondLength = REBOUND_STATE_SIZE, "state size")
	For Local index:Int = 0 Until Int(firstLength)
		Check(firstState[index] = secondState[index], "deterministic state")
	Next
	If first.Score(0) Or first.Score(1) Then sawPoint = True
Next

Check(sawPoint, "simulation scores points")
Local restored:TReboundSimulation = New TReboundSimulation
restored.Reset(1)
Check(restored.LoadState(New SPacketView(Byte Ptr(firstState), REBOUND_STATE_SIZE)), "restore state")
Local restoredState:Byte[REBOUND_STATE_SIZE]
Check(restored.SaveState(Byte Ptr(restoredState), Size_T(restoredState.Length)) = REBOUND_STATE_SIZE, "save restored state")
For Local index:Int = 0 Until restoredState.Length
	Check(restoredState[index] = firstState[index], "state round trip")
Next

Print "GameKit Rebound protocol tests passed"
