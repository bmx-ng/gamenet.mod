SuperStrict

Framework BRL.StandardIO
Import GameNet.Rollback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(RollbackFrameDelta(1, $ffffffff:UInt) = 2, "wrapped frame delta")
Check(RollbackFrameAfter(1, $ffffffff:UInt), "wrapped frame ordering")
Check(TRollbackBuffer.Create(0, 8, 4, 1) = Null, "reject zero players")
Check(TRollbackBuffer.Create(2, 8, Size_T(-1), 1) = Null, "reject rollback storage overflow")

Local rollback:TRollbackBuffer = TRollbackBuffer.Create(2, 4, 4, 1)
Check(rollback <> Null And rollback.Capacity() = 4 And rollback.MaxPlayers() = 2, "create rollback buffer")
Local state:Byte[4]
state[0] = 1
state[1] = 2
state[2] = 3
state[3] = 4
Check(rollback.SaveState(10, Byte Ptr(state), Size_T(state.Length)), "save frame state")
Local stateView:SPacketView
Check(rollback.GetState(10, stateView) And stateView.Length() = 4 And stateView.Data()[2] = 3, "restore frame state")
Local expectedHash:UInt = RollbackHash32(Byte Ptr(state), Size_T(state.Length))
Check(rollback.StateHash(10) = expectedHash And expectedHash <> 0, "state hash")
Local expectedHash64:ULong = RollbackHash64(Byte Ptr(state), Size_T(state.Length))
Local storedHash64:ULong
Check(rollback.GetStateHash64(10, storedHash64) And storedHash64 = expectedHash64 And expectedHash64 <> 0, "64-bit state hash")

Local left:Byte[1]
Local right:Byte[1]
left[0] = Byte(-1)
right[0] = 1
Check(rollback.ConfirmInput(0, 10, Byte Ptr(right), 1) = ERollbackConfirmResult.Stored, "store local confirmed input")
Check(rollback.PredictInput(1, 10, Byte Ptr(left), 1), "store remote prediction")
Check(rollback.PredictInput(1, 10, Byte Ptr(left), 1), "replace remote prediction")
Local input:SRollbackInput
Check(rollback.GetInput(1, 10, input) And input.Status() = ERollbackInputStatus.Predicted, "read predicted input")
Check(rollback.ConfirmInput(1, 10, Byte Ptr(left), 1) = ERollbackConfirmResult.PredictionMatched, "match prediction")
Check(Not rollback.NeedsRollback(), "matched prediction avoids rollback")
Check(rollback.HasConfirmedFrame() And rollback.ConfirmedFrame() = 10, "advance confirmed frame")

Check(rollback.SaveState(11, Byte Ptr(state), Size_T(state.Length)), "save second state")
Check(rollback.ConfirmInput(0, 11, Byte Ptr(right), 1) = ERollbackConfirmResult.Stored, "confirm second local input")
Check(rollback.PredictInput(1, 11, Byte Ptr(left), 1), "predict second remote input")
Check(rollback.ConfirmInput(1, 11, Byte Ptr(right), 1) = ERollbackConfirmResult.PredictionMismatched, "detect prediction mismatch")
Check(rollback.NeedsRollback() And rollback.RollbackFrame() = 11, "request mismatched frame rollback")
Check(rollback.ConfirmedFrame() = 11, "advance confirmation after mismatch")
Check(rollback.ConfirmInput(1, 11, Byte Ptr(right), 1) = ERollbackConfirmResult.Duplicate, "accept duplicate confirmation")
Check(rollback.ConfirmInput(1, 11, Byte Ptr(left), 1) = ERollbackConfirmResult.Rejected, "reject conflicting confirmation")
rollback.ClearRollback()
Check(Not rollback.NeedsRollback(), "clear rollback request")

Check(rollback.PrepareFrame(12), "prepare third frame")
Check(rollback.ConfirmInput(0, 12, Byte Ptr(right), 1) = ERollbackConfirmResult.Stored, "confirm third local input")
Check(rollback.PredictInput(1, 12, Byte Ptr(right), 1), "store replaceable prediction")
Check(rollback.PredictInput(1, 12, Byte Ptr(left), 1), "replace stale prediction")
Check(rollback.GetInput(1, 12, input) And input.Payload().Data()[0] = left[0], "read replacement prediction")
Check(rollback.ConfirmInput(1, 12, Byte Ptr(right), 1) = ERollbackConfirmResult.PredictionMismatched, "compare replacement prediction")
Check(rollback.PrepareFrame(13), "prepare fourth frame")
Check(rollback.ConfirmInput(0, 13, Byte Ptr(right), 1) = ERollbackConfirmResult.Stored, "confirm fourth local input")
Check(rollback.PredictInput(1, 13, Byte Ptr(left), 1), "predict fourth remote input")
Check(rollback.ConfirmInput(1, 13, Byte Ptr(right), 1) = ERollbackConfirmResult.PredictionMismatched, "detect later mismatch")
Check(rollback.RollbackFrame() = 12, "retain earliest mismatched frame")
rollback.ClearRollback()
Check(rollback.PrepareFrame(14), "advance bounded history")
Check(Not rollback.GetState(10, stateView), "old state overwritten")
Check(Not rollback.PrepareFrame(18), "reject jump beyond capacity")

rollback.Clear()
Check(rollback.PrepareFrame($fffffffe:UInt), "prepare frame near wrap")
Check(rollback.PrepareFrame($ffffffff:UInt), "prepare maximum frame")
Check(rollback.PrepareFrame(0), "prepare wrapped frame")
Check(rollback.LatestFrame() = 0, "latest frame wraps")

' Exercise a complete bounded window repeatedly across UInt wraparound.
Local soak:TRollbackBuffer = TRollbackBuffer.Create(2, 64, 4, 1)
Local soakStart:UInt = $ffff0000:UInt
For Local offset:Int = 0 Until 131072
	Local frame:UInt = soakStart + UInt(offset)
	state[0] = Byte(offset & $ff)
	Check(soak.SaveState(frame, Byte Ptr(state), Size_T(state.Length)), "soak save state")
	Check(soak.ConfirmInput(0, frame, Byte Ptr(right), 1) = ERollbackConfirmResult.Stored, "soak local input")
	Check(soak.ConfirmInput(1, frame, Byte Ptr(left), 1) = ERollbackConfirmResult.Stored, "soak remote input")
Next
Check(soak.LatestFrame() = soakStart + UInt(131071), "soak crossed frame wrap")
Check(soak.HasConfirmedFrame() And soak.ConfirmedFrame() = soak.LatestFrame(), "soak confirmation remained contiguous")

Print "GameNet.Rollback tests passed"
