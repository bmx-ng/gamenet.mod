SuperStrict

Framework BRL.StandardIO
Import GameNet.Core

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local bytes:Byte[24]
Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(bytes), Size_T(bytes.Length))

Check(writer.WriteUInt8($ab), "write uint8")
Check(writer.WriteUInt16($cdef), "write uint16")
Check(writer.WriteUInt32($81234567:UInt), "write uint32")
Check(writer.WriteUInt64($fedcba9876543210:ULong), "write uint64")
Check(writer.WriteFloat32(12.5), "write float32")
Check(writer.Position() = 19, "writer position")
Check(Not writer.Failed(), "writer success state")

Local reader:SPacketReader = New SPacketReader(writer.View())
Local u8:UInt
Local u16:UInt
Local u32:UInt
Local u64:ULong
Local f32:Float

Check(reader.ReadUInt8(u8) And u8 = $ab, "read uint8")
Local remaining:SPacketView = reader.RemainingView()
Check(remaining.Length() = 18 And (UInt(remaining.Data()[0]) & $ff:UInt) = $cd, "remaining packet view")
Check(reader.ReadUInt16(u16) And u16 = $cdef, "read uint16")
Check(reader.ReadUInt32(u32) And u32 = $81234567:UInt, "read uint32")
Check(reader.ReadUInt64(u64) And u64 = $fedcba9876543210:ULong, "read uint64")
Check(reader.ReadFloat32(f32) And f32 = 12.5, "read float32")
Check(reader.Remaining() = 0, "reader consumed packet")
Check(Not reader.ReadUInt8(u8), "reader rejects overflow")
Check(reader.Failed(), "reader failure is sticky")

Local small:Byte[1]
Local shortWriter:SPacketWriter = New SPacketWriter(Byte Ptr(small), Size_T(small.Length))
Check(Not shortWriter.WriteUInt16(1), "writer rejects overflow")
Check(shortWriter.Position() = 0, "failed write is atomic")

Local first:SNetPeer = New SNetPeer(7, 2)
Local same:SNetPeer = New SNetPeer(7, 2)
Local stale:SNetPeer = New SNetPeer(7, 1)
Local invalid:SNetPeer
Check(first.IsValid(), "peer is valid")
Check(first.Equals(same), "peer equality")
Check(Not first.Equals(stale), "peer generation")
Check(Not invalid.IsValid(), "default peer is invalid")

Check(GAMENET_RECOMMENDED_INTERNET_PACKET_SIZE = 1200, "conservative Internet packet guidance")
Local storage:Size_T
Check(NetAccumulateSize(storage, 4, 8) And storage = 32, "accumulate storage size")
Check(NetAccumulateSize(storage, 2, 16) And storage = 64, "accumulate storage total")
Local maximum:Size_T = Size_T(-1)
storage = maximum - 1
Check(Not NetAccumulateSize(storage, 1, 2) And storage = maximum - 1, "reject storage addition overflow")
storage = 0
Check(Not NetAccumulateSize(storage, maximum, 2) And storage = 0, "reject storage multiplication overflow")

Print "GameNet.Core tests passed"
