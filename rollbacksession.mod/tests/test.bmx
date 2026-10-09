SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSession

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Type TTestSimulation Implements IRollbackSimulation, IRollbackEffectSimulation
	Field position0:Int
	Field position1:Int

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(position0))
		writer.WriteUInt32(UInt(position1))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Local value0:UInt
		Local value1:UInt
		If Not reader.ReadUInt32(value0) Or Not reader.ReadUInt32(value1) Or reader.Remaining() <> 0 Then Return False
		position0 = Int(value0)
		position1 = Int(value1)
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then Return 0
		buffer[0] = 0
		If Not previous.IsEmpty() Then buffer[0] = previous.Data()[0]
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		Return SimulateFrame(frame, inputs, Null)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[], effects:IRollbackEffectWriter)
		If inputs.Length <> 2 Or inputs[0].Payload().Length() <> 1 Or inputs[1].Payload().Length() <> 1 Then Return False
		position0 :+ Int(Byte(inputs[0].Payload().Data()[0]))
		position1 :+ Int(Byte(inputs[1].Payload().Data()[0]))
		Local payload:Byte[1]
		payload[0] = Byte(frame & $ff)
		If effects Then Return effects.Emit(1, Byte Ptr(payload), 1)
		Return True
	End Method
End Type

Type TPlainSimulation Implements IRollbackSimulation
	Field value:UInt

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(value)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Return reader.ReadUInt32(value) And reader.Remaining() = 0
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then Return 0
		buffer[0] = 0
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		value :+ 1
		Return True
	End Method
End Type

Local invalid:SRollbackSessionConfig = New SRollbackSessionConfig(1, 0, 32, 8, 1)
Check(TRollbackSession.Create(New TTestSimulation, invalid) = Null, "reject one-player session")

Local plainSimulation:TPlainSimulation = New TPlainSimulation
Local plainConfig:SRollbackSessionConfig = New SRollbackSessionConfig(2, 0, 32, 4, 1)
Local plainSession:TRollbackSession = TRollbackSession.Create(plainSimulation, plainConfig)
Local plainNeutral:Byte[1]
Check(plainSession.Start(Byte Ptr(plainNeutral), 1), "start simulation without effect source")
Check(plainSession.Step(Byte Ptr(plainNeutral), 1), "advance simulation without effect source")
Check(plainSession.PendingConfirmedEffects() = 0, "effect support remains optional")

Local simulation0:TTestSimulation = New TTestSimulation
Local simulation1:TTestSimulation = New TTestSimulation
Local config0:SRollbackSessionConfig = New SRollbackSessionConfig(2, 0, 128, 8, 1, 3, 8, 12, 10, 16)
Local config1:SRollbackSessionConfig = New SRollbackSessionConfig(2, 1, 128, 8, 1, 3, 8, 12, 10, 16)
Local session0:TRollbackSession = TRollbackSession.Create(simulation0, config0)
Local session1:TRollbackSession = TRollbackSession.Create(simulation1, config1)
Check(session0 <> Null And session1 <> Null, "create rollback sessions")

Local neutral:Byte[1]
Check(session0.Start(Byte Ptr(neutral), 1) And session1.Start(Byte Ptr(neutral), 1), "start rollback sessions")
Local packet0:Byte[256]
Local packet1:Byte[256]
Local effectCount0:Int
Local effectCount1:Int
Local lastEffectFrame0:UInt
Local lastEffectFrame1:UInt

For Local frame:Int = 0 Until 150
	Local input0:Byte[1]
	Local input1:Byte[1]
	If (frame / 11) Mod 2 = 0 Then input0[0] = 1 Else input0[0] = Byte(-1)
	If (frame / 13) Mod 2 = 0 Then input1[0] = Byte(-1) Else input1[0] = 1
	Check(session0.CanStep() And session1.CanStep(), "sessions can advance")
	Check(session0.Step(Byte Ptr(input0), 1) And session1.Step(Byte Ptr(input1), 1), "advance sessions")

	' Deliver every fourth frame so both peers must predict and occasionally roll back.
	If frame Mod 4 = 3 Then
		Local length0:Size_T = session0.WriteInputs(Byte Ptr(packet0), Size_T(packet0.Length))
		Local length1:Size_T = session1.WriteInputs(Byte Ptr(packet1), Size_T(packet1.Length))
		Check(length0 > 0 And length1 > 0, "write redundant inputs")
		Check(session1.ReceiveInputs(0, New SPacketView(Byte Ptr(packet0), length0)), "receive player zero inputs")
		Check(session0.ReceiveInputs(1, New SPacketView(Byte Ptr(packet1), length1)), "receive player one inputs")
	End If

	Local hashLength0:Size_T = session0.WriteReadyHash(Byte Ptr(packet0), Size_T(packet0.Length))
	If hashLength0 > 0 Then Check(session1.ReceiveHash(New SPacketView(Byte Ptr(packet0), hashLength0)), "receive player zero hash")
	Local hashLength1:Size_T = session1.WriteReadyHash(Byte Ptr(packet1), Size_T(packet1.Length))
	If hashLength1 > 0 Then Check(session0.ReceiveHash(New SPacketView(Byte Ptr(packet1), hashLength1)), "receive player one hash")

	Local effect:SRollbackEffect
	While session0.PollConfirmedEffect(effect)
		Check(effect.Kind() = 1 And effect.Payload().Length() = 1, "player zero confirmed effect")
		If effectCount0 > 0 Then Check(RollbackFrameAfter(effect.Frame(), lastEffectFrame0), "player zero effect order")
		lastEffectFrame0 = effect.Frame()
		effectCount0 :+ 1
	Wend
	While session1.PollConfirmedEffect(effect)
		Check(effect.Kind() = 1 And effect.Payload().Length() = 1, "player one confirmed effect")
		If effectCount1 > 0 Then Check(RollbackFrameAfter(effect.Frame(), lastEffectFrame1), "player one effect order")
		lastEffectFrame1 = effect.Frame()
		effectCount1 :+ 1
	Wend
Next

' Deliver the final batch and run one frame to apply any pending rollback.
Local finalLength0:Size_T = session0.WriteInputs(Byte Ptr(packet0), Size_T(packet0.Length))
Local finalLength1:Size_T = session1.WriteInputs(Byte Ptr(packet1), Size_T(packet1.Length))
Check(session1.ReceiveInputs(0, New SPacketView(Byte Ptr(packet0), finalLength0)), "receive final player zero inputs")
Check(session0.ReceiveInputs(1, New SPacketView(Byte Ptr(packet1), finalLength1)), "receive final player one inputs")
Local zero:Byte[1]
Check(session0.Step(Byte Ptr(zero), 1) And session1.Step(Byte Ptr(zero), 1), "resolve final rollback")

Local finalEffect:SRollbackEffect
While session0.PollConfirmedEffect(finalEffect)
	lastEffectFrame0 = finalEffect.Frame()
	effectCount0 :+ 1
Wend
While session1.PollConfirmedEffect(finalEffect)
	lastEffectFrame1 = finalEffect.Frame()
	effectCount1 :+ 1
Wend

Check(simulation0.position0 = simulation1.position0 And simulation0.position1 = simulation1.position1, "converged deterministic state")
Check(session0.RollbackCount() > 0 And session1.RollbackCount() > 0, "rollback occurred")
Check(session0.PredictionMismatches() > 0 And session1.PredictionMismatches() > 0, "prediction mismatch detected")
Check(session0.HashesChecked() > 0 And session1.HashesChecked() > 0, "confirmed hashes checked")
Check(session0.HashMismatches() = 0 And session1.HashMismatches() = 0, "no deterministic desync")
Check(effectCount0 = 151 And effectCount1 = 151, "confirmed effects released once")
Check(lastEffectFrame0 = 150 And lastEffectFrame1 = 150, "confirmed effects cover simulated frames")
Check(session0.DroppedConfirmedEffects() = 0 And session1.DroppedConfirmedEffects() = 0, "confirmed effect queue did not overflow")
Check(Not session0.Failed() And Not session1.Failed(), "sessions remained healthy")

Print "GameNet.RollbackSession tests passed"
