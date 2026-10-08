SuperStrict

Framework BRL.StandardIO
Import GameNet.Core

Include "protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local buffer:Byte[32]

Local length:Size_T = EncodeInput(Byte Ptr(buffer), Size_T(buffer.Length), 42, -127, 91)
Check(length = 6, "input size")
Local sequence:UInt
Local axisX:Int
Local axisY:Int
Check(DecodeInput(New SPacketView(Byte Ptr(buffer), length), sequence, axisX, axisY), "decode input")
Check(sequence = 42 And axisX = -127 And axisY = 91, "input values")
Check(Not DecodeInput(New SPacketView(Byte Ptr(buffer), length - 1), sequence, axisX, axisY), "reject truncated input")
Check(Not DecodeInput(New SPacketView(Byte Ptr(buffer), length + 1), sequence, axisX, axisY), "reject input trailing data")

length = EncodeSpawn(Byte Ptr(buffer), Size_T(buffer.Length), 7, 123.5, 99.25)
Check(length = 12, "spawn size")
Local entityId:UInt
Local x:Float
Local y:Float
Check(DecodeSpawn(New SPacketView(Byte Ptr(buffer), length), entityId, x, y), "decode spawn")
Check(entityId = 7 And x = 123.5 And y = 99.25, "spawn values")

length = EncodeSnapshot(Byte Ptr(buffer), Size_T(buffer.Length), 600, 57, 22.5, 300.75)
Check(length = 16, "snapshot size")
Local tick:UInt
Local acknowledgedInput:UInt
Check(DecodeSnapshot(New SPacketView(Byte Ptr(buffer), length), tick, acknowledgedInput, x, y), "decode snapshot")
Check(tick = 600 And acknowledgedInput = 57 And x = 22.5 And y = 300.75, "snapshot values")

Check(EncodeSnapshot(Byte Ptr(buffer), 8, 1, 2, 3.0, 4.0) = 0, "bounded snapshot encode")

Print "Authoritative example protocol tests passed"
