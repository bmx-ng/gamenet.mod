SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSpectator

Function Check(condition:Int, message:String)
	If Not condition Then
		Throw "FAILED: " + message
	End If
End Function

Function WriteRemoteInput:Size_T(buffer:Byte Ptr, capacity:Size_T, simulatedFrame:UInt, inputFrame:UInt, value:Byte)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(simulatedFrame)
	writer.WriteUInt8(1)
	writer.WriteUInt32(inputFrame)
	writer.WriteUInt16(1)
	writer.WriteUInt8(UInt(value) & $ff:UInt)
	If writer.Failed() Then
		Return 0
	End If
	Return writer.Position()
End Function

Type TSpectatorSimulation Implements IRollbackSimulation
	Field values:Int[2]

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(values[0]))
		writer.WriteUInt32(UInt(values[1]))
		If writer.Failed() Then
			Return 0
		End If
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Local value0:UInt
		Local value1:UInt
		If Not reader.ReadUInt32(value0) Or Not reader.ReadUInt32(value1) Or reader.Remaining() <> 0 Then
			Return False
		End If
		values[0] = Int(value0)
		values[1] = Int(value1)
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then
			Return 0
		End If
		buffer[0] = 0
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		If inputs.Length <> 2 Then
			Return False
		End If
		For Local player:Int = 0 Until 2
			If inputs[player].Payload().Length() <> 1 Then
				Return False
			End If
			values[player] :+ Int(Byte(inputs[player].Payload().Data()[0]))
		Next
		Return True
	End Method
End Type

Local sourceSimulation:TSpectatorSimulation = New TSpectatorSimulation
Local config:SRollbackSessionConfig = New SRollbackSessionConfig(2, 0, 64, 8, 1, 0, 8, 8)
Local sourceSession:TRollbackSession = TRollbackSession.Create(sourceSimulation, config)
Local neutral:Byte[1]
Check(sourceSession.Start(Byte Ptr(neutral), 1), "start source rollback session")

Local remotePacket:Byte[32]
Local localInput:Byte[1]
localInput[0] = 1
For Local frame:UInt = 0 Until 5
	Check(sourceSession.Step(Byte Ptr(localInput), 1), "advance source before spectator joins")
	Local remoteLength:Size_T = WriteRemoteInput(Byte Ptr(remotePacket), Size_T(remotePacket.Length), frame + 1, frame, 0)
	Check(sourceSession.ReceiveInputs(1, New SPacketView(Byte Ptr(remotePacket), remoteLength)), "confirm remote source input")
Next

Local source:TRollbackSpectatorSource = TRollbackSpectatorSource.Create(sourceSession)
Check(source <> Null And source.PrepareBootstrap(), "prepare mid-match spectator bootstrap")
Local packet:Byte[128]
Local bootstrapLength:Size_T = source.WriteBootstrap(Byte Ptr(packet), Size_T(packet.Length))
Check(bootstrapLength > 0, "write spectator bootstrap")

Local spectatorSimulation:TSpectatorSimulation = New TSpectatorSimulation
Local spectator:TRollbackSpectatorSession = TRollbackSpectatorSession.Create(spectatorSimulation, 2, 8, 1)
Check(spectator.ReceiveBootstrap(New SPacketView(Byte Ptr(packet), bootstrapLength)), "load confirmed spectator bootstrap")
Check(source.CommitBootstrap(source.BootstrapFrame()), "commit spectator bootstrap")
Check(spectator.CurrentFrame() = 5 And spectatorSimulation.values[0] = 5, "spectator joins at confirmed state")

For Local frame:UInt = 5 Until 15
	Check(sourceSession.Step(Byte Ptr(localInput), 1), "advance live source")
	Local remoteLength:Size_T = WriteRemoteInput(Byte Ptr(remotePacket), Size_T(remotePacket.Length), frame + 1, frame, 0)
	Check(sourceSession.ReceiveInputs(1, New SPacketView(Byte Ptr(remotePacket), remoteLength)), "confirm live source input")
Next

Check(source.BacklogFrames() = 10, "measure spectator backlog")
Check(source.NeedsRebootstrap(8) And Not source.NeedsRebootstrap(10), "apply bounded slow-spectator policy")
Check(source.BatchPacketCapacity(4) >= 11 + 4 * (4 + 2 * 3), "report spectator batch capacity")

' The single-frame form remains useful for live playback at normal speed.
Local frameLength:Size_T = source.WriteNextFrame(Byte Ptr(packet), Size_T(packet.Length))
Check(frameLength > 0, "write confirmed spectator frame")
Check(spectator.ReceiveFrame(New SPacketView(Byte Ptr(packet), frameLength)), "play confirmed spectator frame")
Check(source.CommitFrame(5), "commit confirmed spectator frame")

' A lagging spectator catches up in bounded batches. Writing is non-consuming,
' and the exact pending range must be committed after transport acceptance.
While source.BacklogFrames() > 0
	Local firstFrame:UInt = source.NextFrame()
	Local batchLength:Size_T = source.WriteNextFrames(Byte Ptr(packet), Size_T(packet.Length), 4)
	Local batchCount:Int = source.PendingFrameCount()
	Check(batchLength > 0 And batchCount >= 1 And batchCount <= 4, "write bounded spectator batch")
	Check(Not source.CommitFrames(firstFrame, batchCount + 1), "reject incorrect spectator batch commit")
	Check(spectator.ReceiveFrames(New SPacketView(Byte Ptr(packet), batchLength)), "play confirmed spectator batch")
	Check(source.CommitFrames(firstFrame, batchCount), "commit confirmed spectator batch")
Wend

Check(spectator.FramesPlayed() = 10 And spectator.CurrentFrame() = 15, "spectator timeline remains sequential")
Check(spectatorSimulation.values[0] = sourceSimulation.values[0] And spectatorSimulation.values[1] = sourceSimulation.values[1], "spectator converges with live source")
Check(Not spectator.Failed(), "spectator remains healthy")

Print "GameNet.RollbackSpectator tests passed"
