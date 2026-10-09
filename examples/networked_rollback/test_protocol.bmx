SuperStrict

Framework BRL.StandardIO
Import GameNet.Rollback

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

Local frames:UInt[ROLLBACK_INPUT_BATCH_MAX]
Local axisXs:Int[ROLLBACK_INPUT_BATCH_MAX]
Local axisYs:Int[ROLLBACK_INPUT_BATCH_MAX]
frames[0] = 40
frames[1] = 41
frames[2] = 42
axisXs[0] = -1
axisXs[1] = 0
axisXs[2] = 1
axisYs[0] = 1
axisYs[1] = -1
axisYs[2] = 0
length = EncodeRollbackInputBatch(Byte Ptr(buffer), Size_T(buffer.Length), 39, frames, axisXs, axisYs, 3)
Check(length = 23, "input batch size")
Local decodedFrame:UInt
Local decodedFrames:UInt[ROLLBACK_INPUT_BATCH_MAX]
Local decodedXs:Int[ROLLBACK_INPUT_BATCH_MAX]
Local decodedYs:Int[ROLLBACK_INPUT_BATCH_MAX]
Local decodedCount:Int
Check(DecodeRollbackInputBatch(New SPacketView(Byte Ptr(buffer), length), decodedFrame, decodedFrames, decodedXs, decodedYs, decodedCount), "decode input batch")
Check(decodedFrame = 39 And decodedCount = 3, "input batch header")
Check(decodedFrames[2] = 42 And decodedXs[0] = -1 And decodedYs[1] = -1, "input batch values")
frames[2] = 41
Check(EncodeRollbackInputBatch(Byte Ptr(buffer), Size_T(buffer.Length), 39, frames, axisXs, axisYs, 3) = 0, "reject unordered input batch")

length = EncodeStateHash(Byte Ptr(buffer), Size_T(buffer.Length), 120, $89abcdef:UInt)
Local hashFrame:UInt
Local hash:UInt
Check(length = 8 And DecodeStateHash(New SPacketView(Byte Ptr(buffer), length), hashFrame, hash), "decode state hash")
Check(hashFrame = 120 And hash = $89abcdef:UInt, "state hash values")

length = EncodePing(Byte Ptr(buffer), Size_T(buffer.Length), 7654)
Local token:UInt
Check(DecodePing(New SPacketView(Byte Ptr(buffer), length), token) And token = 7654, "ping token")

Print "Networked rollback protocol tests passed"
