SuperStrict

Framework BRL.StandardIO
Import GameNet.Core
Import GameNet.Prediction

Include "protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local buffer:Byte[512]

Local length:Size_T = EncodeMovementInput(Byte Ptr(buffer), Size_T(buffer.Length), -127, 91)
Check(length = 2, "movement input size")
Local axisX:Int
Local axisY:Int
Check(DecodeMovementInput(New SPacketView(Byte Ptr(buffer), length), axisX, axisY), "decode movement input")
Check(axisX = -127 And axisY = 91, "movement input values")
Check(Not DecodeMovementInput(New SPacketView(Byte Ptr(buffer), length - 1), axisX, axisY), "reject truncated movement input")
Check(Not DecodeMovementInput(New SPacketView(Byte Ptr(buffer), length + 1), axisX, axisY), "reject movement input trailing data")

Local history:TPredictionHistory = TPredictionHistory.Create(AUTHORITATIVE_INPUT_HISTORY_CAPACITY, AUTHORITATIVE_INPUT_PAYLOAD_SIZE)
Local payload:Byte[AUTHORITATIVE_INPUT_PAYLOAD_SIZE]
Check(EncodeMovementInput(Byte Ptr(payload), Size_T(payload.Length), -10, 20) = AUTHORITATIVE_INPUT_PAYLOAD_SIZE, "encode first history input")
Check(history.Add(41, Byte Ptr(payload), Size_T(payload.Length)), "add first history input")
Check(EncodeMovementInput(Byte Ptr(payload), Size_T(payload.Length), 30, -40) = AUTHORITATIVE_INPUT_PAYLOAD_SIZE, "encode second history input")
Check(history.Add(42, Byte Ptr(payload), Size_T(payload.Length)), "add second history input")
length = EncodeInputBatch(Byte Ptr(buffer), Size_T(buffer.Length), history)
Check(length = 13, "input batch size")
Local sequences:UInt[AUTHORITATIVE_INPUT_HISTORY_CAPACITY]
Local axisXs:Int[AUTHORITATIVE_INPUT_HISTORY_CAPACITY]
Local axisYs:Int[AUTHORITATIVE_INPUT_HISTORY_CAPACITY]
Local inputCount:Int
Check(DecodeInputBatch(New SPacketView(Byte Ptr(buffer), length), sequences, axisXs, axisYs, inputCount), "decode input batch")
Check(inputCount = 2 And sequences[0] = 41 And sequences[1] = 42, "input batch sequences")
Check(axisXs[0] = -10 And axisYs[0] = 20 And axisXs[1] = 30 And axisYs[1] = -40, "input batch values")
Check(Not DecodeInputBatch(New SPacketView(Byte Ptr(buffer), length - 1), sequences, axisXs, axisYs, inputCount), "reject truncated input batch")
Check(Not DecodeInputBatch(New SPacketView(Byte Ptr(buffer), length + 1), sequences, axisXs, axisYs, inputCount), "reject input batch trailing data")
Check(EncodeInputBatch(Byte Ptr(buffer), 8, history) = 0, "bounded input batch encode")

length = EncodeEntity(Byte Ptr(buffer), Size_T(buffer.Length), 3)
Check(length = 4, "entity size")
Local entityId:UInt
Check(DecodeEntity(New SPacketView(Byte Ptr(buffer), length), entityId), "decode entity")
Check(entityId = 3, "entity value")

length = EncodeSpawn(Byte Ptr(buffer), Size_T(buffer.Length), 7, 123.5, 99.25)
Check(length = 12, "spawn size")
Local x:Float
Local y:Float
Check(DecodeSpawn(New SPacketView(Byte Ptr(buffer), length), entityId, x, y), "decode spawn")
Check(entityId = 7 And x = 123.5 And y = 99.25, "spawn values")

length = EncodeSnapshot(Byte Ptr(buffer), Size_T(buffer.Length), 3, 600, 57, 22.5, 300.75)
Check(length = 20, "snapshot size")
Local tick:UInt
Local acknowledgedInput:UInt
Check(DecodeSnapshot(New SPacketView(Byte Ptr(buffer), length), entityId, tick, acknowledgedInput, x, y), "decode snapshot")
Check(entityId = 3 And tick = 600 And acknowledgedInput = 57 And x = 22.5 And y = 300.75, "snapshot values")

Check(EncodeSnapshot(Byte Ptr(buffer), 8, 1, 2, 3, 4.0, 5.0) = 0, "bounded snapshot encode")

Print "Authoritative example protocol tests passed"
