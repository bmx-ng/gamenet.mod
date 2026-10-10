SuperStrict

Framework BRL.StandardIO
Import GameNet.Prediction

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function PayloadValue:Int(input:SPredictionInput)
	If input.Payload().Length() <> 1 Then Throw "invalid input payload"
	Return UInt(input.Payload().Data()[0]) & $ff:UInt
End Function

Check(PredictionSequenceDelta(5, 3) = 2, "forward sequence delta")
Check(PredictionSequenceDelta(1, $ffffffff:UInt) = 2, "wrapped sequence delta")
Check(PredictionSequenceAfter(1, $ffffffff:UInt), "wrapped sequence ordering")
Check(Not PredictionSequenceAfter(9, 9), "equal sequence ordering")

Check(TPredictionHistory.Create(0, 1) = Null, "reject zero history capacity")
Check(TPredictionHistory.Create(2, Size_T(-1)) = Null, "reject prediction storage overflow")
Local history:TPredictionHistory = TPredictionHistory.Create(3, 2)
Check(history <> Null And history.Capacity() = 3, "create history")
Local payloads:Byte[5]
payloads[0] = 10
payloads[1] = 20
payloads[2] = 30
payloads[3] = 40
payloads[4] = 50

Check(history.Add(10, Byte Ptr(payloads), 1), "add first input")
Check(history.Add(11, Byte Ptr(payloads) + 1, 1), "add second input")
Check(history.Add(12, Byte Ptr(payloads) + 2, 1), "add third input")
Check(history.Count() = 3 And history.OldestSequence() = 10 And history.LatestSequence() = 12, "history metadata")
Check(Not history.Add(13, Byte Ptr(payloads) + 3, 1), "full history rejects input")

Local input:SPredictionInput
Check(history.Get(0, input) And input.Sequence() = 10 And PayloadValue(input) = 10, "read oldest input")
Check(history.Get(2, input) And input.Sequence() = 12 And PayloadValue(input) = 30, "read newest input")
Check(Not history.Get(3, input), "reject out-of-range input")
Check(history.Acknowledge(9) = 0, "ignore old acknowledgement")
Check(history.Acknowledge(11) = 2, "remove acknowledged inputs")
Check(history.Count() = 1 And history.OldestSequence() = 12, "retain unacknowledged input")
Check(history.Add(13, Byte Ptr(payloads) + 3, 1), "reuse acknowledged slot")
Check(history.Add(14, Byte Ptr(payloads) + 4, 1), "wrap history storage")
Check(Not history.Add(14, Byte Ptr(payloads), 1), "reject duplicate input")
Check(history.Acknowledge(14) = 3 And history.Count() = 0, "acknowledge all inputs")

history.Clear()
Check(history.Add($ffffffff:UInt, Byte Ptr(payloads), 1), "add input near wrap")
Check(history.Add(0, Byte Ptr(payloads) + 1, 1), "add wrapped input")
Check(history.Add(1, Byte Ptr(payloads) + 2, 1), "add input after wrap")
Check(history.Acknowledge(0) = 2, "acknowledge across wrap")
Check(history.Count() = 1 And history.OldestSequence() = 1, "retain input after wrapped acknowledgement")
Check(Not history.Add(2, Byte Ptr(payloads), 3), "reject oversized payload")

Local sequencer:SPredictionSequencer
sequencer.Reset(10)
Check(sequencer.NextSequence() = 10 And Not sequencer.HasProcessed(), "reset sequencer")
Check(sequencer.Process(11) = EPredictionSequenceResult.Gap, "report sequence gap")
Check(sequencer.NextSequence() = 10, "gap does not advance")
Check(sequencer.Process(10) = EPredictionSequenceResult.Accepted, "accept expected sequence")
Check(sequencer.LastProcessed() = 10 And sequencer.NextSequence() = 11, "advance sequencer")
Check(sequencer.Process(10) = EPredictionSequenceResult.Duplicate, "reject duplicate sequence")
Check(sequencer.Process(11) = EPredictionSequenceResult.Accepted, "accept filled gap")

sequencer.Reset($ffffffff:UInt)
Check(sequencer.Process($ffffffff:UInt) = EPredictionSequenceResult.Accepted, "accept sequence near wrap")
Check(sequencer.Process(0) = EPredictionSequenceResult.Accepted, "accept wrapped sequence")
Check(sequencer.NextSequence() = 1, "advance after wrap")

Print "GameNet.Prediction tests passed"
