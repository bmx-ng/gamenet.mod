SuperStrict

Framework BRL.StandardIO
Import GameNet.Core

Include "protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local buffer:Byte[128]
Local length:Size_T = EncodePlayerAssignment(Byte Ptr(buffer), Size_T(buffer.Length), 1)
Local player:Int
Check(length = 1 And DecodePlayerAssignment(New SPacketView(Byte Ptr(buffer), length), player) And player = 1, "player assignment")
Check(EncodePlayerAssignment(Byte Ptr(buffer), Size_T(buffer.Length), 2) = 0, "invalid player assignment")

length = EncodeMatch(Byte Ptr(buffer), Size_T(buffer.Length), $12345678:UInt)
Local matchId:UInt
Check(DecodeMatch(New SPacketView(Byte Ptr(buffer), length), matchId) And matchId = $12345678:UInt, "match identifier")

length = EncodePing(Byte Ptr(buffer), Size_T(buffer.Length), 7654)
Local token:UInt
Check(DecodePing(New SPacketView(Byte Ptr(buffer), length), token) And token = 7654, "ping token")

Print "Networked rollback protocol tests passed"
