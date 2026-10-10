SuperStrict

Framework BRL.StandardIO
Import GameNet.Core

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

length = EncodePositionState(Byte Ptr(buffer), Size_T(buffer.Length), 22.5, 300.75)
Check(length = AUTHORITATIVE_SNAPSHOT_STATE_SIZE, "position state size")
Check(DecodePositionState(New SPacketView(Byte Ptr(buffer), length), x, y), "decode position state")
Check(x = 22.5 And y = 300.75, "position state values")
Check(EncodePositionState(Byte Ptr(buffer), 4, 4.0, 5.0) = 0, "bounded position state encode")

Print "Authoritative example protocol tests passed"
