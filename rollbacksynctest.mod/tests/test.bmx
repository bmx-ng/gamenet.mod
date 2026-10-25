SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSyncTest

Function Check(condition:Int, message:String)
	If Not condition Then
		Throw "FAILED: " + message
	End If
End Function

Type TSyncSimulation Implements IRollbackSimulation
	Field value:UInt
	Field hiddenCounter:UInt
	Field nondeterministic:Int

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If capacity < 4 Then
			Return 0
		End If
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(value)
		If writer.Failed() Then
			Return 0
		End If
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Return reader.ReadUInt32(value) And reader.Remaining() = 0
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		Return 0
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		If inputs.Length <> 1 Or inputs[0].Payload().Length() <> 1 Then
			Return False
		End If
		value :+ UInt(inputs[0].Payload().Data()[0])
		If nondeterministic Then
			hiddenCounter :+ 1
			value :+ hiddenCounter
		End If
		Return True
	End Method
End Type

Local inputByte:Byte[1]
inputByte[0] = 2
Local inputs:SRollbackInput[1]
inputs[0] = New SRollbackInput(0, 0, ERollbackInputStatus.Confirmed, New SPacketView(Byte Ptr(inputByte), 1))

Local deterministic:TSyncSimulation = New TSyncSimulation
Local syncTest:TRollbackSyncTest = TRollbackSyncTest.Create(deterministic, 4)
Check(syncTest <> Null, "create sync test")
For Local frame:UInt = 0 Until 120
	inputs[0] = New SRollbackInput(frame, 0, ERollbackInputStatus.Confirmed, New SPacketView(Byte Ptr(inputByte), 1))
	Check(syncTest.Step(frame, inputs), "deterministic frame passes")
Next
Check(Not syncTest.Failed() And syncTest.TestedFrames() = 120, "all deterministic frames tested")
Check(deterministic.value = 240, "sync test advances once externally")

Local divergent:TSyncSimulation = New TSyncSimulation
divergent.nondeterministic = True
syncTest = TRollbackSyncTest.Create(divergent, 4)
Check(Not syncTest.Step(17, inputs), "hidden state is detected")
Check(syncTest.Failed(), "divergent sync test fails")
Check(syncTest.FailureReason() = ERollbackSyncTestFailure.StateContentMismatch, "report content mismatch")
Check(syncTest.FailureFrame() = 17 And syncTest.MismatchOffset() < 4, "locate divergent frame and byte")
Check(divergent.value = 3, "restore first execution result after mismatch")

Print "GameNet.RollbackSyncTest tests passed"
