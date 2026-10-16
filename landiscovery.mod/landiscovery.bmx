' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages
' arising from the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
' 1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
' 2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
' 3. This notice may not be removed or altered from any source distribution.

SuperStrict

Rem
bbdoc: Local-network game discovery for GameNet transports.
End Rem
Module GameNet.LANDiscovery

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial query and response discovery protocol"

Import GameNet.Core
Import BRL.Socket
Import BRL.System
Import Pub.Net

Const GAMENET_LAN_DISCOVERY_PORT:Int = 46291
Const GAMENET_LAN_QUERY_INTERVAL_MILLIS:UInt = 1000
Const GAMENET_LAN_RESULT_EXPIRY_MILLIS:UInt = 3500
Const GAMENET_LAN_MAX_RESULTS:Int = 32
Const GAMENET_LAN_MAX_PACKETS_PER_UPDATE:Int = 64
Const GAMENET_LAN_MAX_GAME_ID_BYTES:Int = 63
Const GAMENET_LAN_MAX_NAME_BYTES:Int = 95
Const GAMENET_LAN_MAX_METADATA_BYTES:Int = 511
Const GAMENET_LAN_BROADCAST_ADDRESS:String = "255.255.255.255"

Private

Const LAN_DISCOVERY_MAGIC:UInt = $474e4c31
Const LAN_DISCOVERY_PROTOCOL_VERSION:UInt = 1
Const LAN_DISCOVERY_QUERY:UInt = 1
Const LAN_DISCOVERY_RESPONSE:UInt = 2
Const LAN_DISCOVERY_PACKET_BYTES:Int = 768

Function WriteUTF8:Int(writer:SPacketWriter Var, value:String, maximumBytes:Int, wideLength:Int = False)
	Local length:Size_T
	Local bytes:Byte Ptr = value.ToUTF8String(length)
	If length > Size_T(maximumBytes) Then
		MemFree(bytes)
		Return False
	End If
	Local result:Int
	If wideLength Then
		result = writer.WriteUInt16(UInt(length))
	Else
		result = writer.WriteUInt8(UInt(length))
	End If
	If result Then result = writer.WriteBytes(bytes, length)
	MemFree(bytes)
	Return result
End Function

Function ReadUTF8:Int(reader:SPacketReader Var, value:String Var, maximumBytes:Int, wideLength:Int = False)
	Local length:UInt
	If wideLength Then
		If Not reader.ReadUInt16(length) Then Return False
	Else
		If Not reader.ReadUInt8(length) Then Return False
	End If
	If length > UInt(maximumBytes) Or Size_T(length) > reader.Remaining() Then Return False
	Local bytes:Byte[] = New Byte[Int(length)]
	If length > 0 And Not reader.ReadBytes(Byte Ptr(bytes), Size_T(length)) Then Return False
	value = String.FromUTF8Bytes(bytes, bytes.Length)
	Return True
End Function

Function ValidUTF8Length:Int(value:String, maximumBytes:Int)
	Local length:Size_T
	Local bytes:Byte Ptr = value.ToUTF8String(length)
	MemFree(bytes)
	Return length <= Size_T(maximumBytes)
End Function

Function IPv4String:String(address:Int)
	Local value:UInt = UInt(address)
	Return String((value Shr 24) & $ff:UInt) + "." + String((value Shr 16) & $ff:UInt) + "." + ..
		String((value Shr 8) & $ff:UInt) + "." + String(value & $ff:UInt)
End Function

Function SendDatagram:Int(socket:TSocket, buffer:Byte[], length:Size_T, address:String, port:Int)
	If Not socket Or length = 0 Or length > Size_T(buffer.Length) Or address.Length = 0 Or port < 1 Or port > 65535 Then Return False
	Local destination:Byte Ptr = address.ToCString()
	Local sent:Int = sendto_(socket.Socket(), Byte Ptr(buffer), Int(length), 0, destination, port, AF_INET_)
	MemFree(destination)
	Return sent = Int(length)
End Function

Function DatagramReady:Int(socket:TSocket)
	If Not socket Then Return False
?Not win32
	Local handle:Int = socket.Socket()
?win32 And ptr32
	Local handle:Int = socket.Socket()
?win32 And ptr64
	Local handle:Long = socket.Socket()
?
	Return select_(1, Varptr handle, 0, Null, 0, Null, 0) = 1
End Function

Function EncodeQuery:Size_T(buffer:Byte[], gameId:String, protocolVersion:UInt)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(buffer), Size_T(buffer.Length))
	If Not writer.WriteUInt32(LAN_DISCOVERY_MAGIC) Or Not writer.WriteUInt8(LAN_DISCOVERY_PROTOCOL_VERSION) Or ..
		Not writer.WriteUInt8(LAN_DISCOVERY_QUERY) Or Not WriteUTF8(writer, gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) Or ..
		Not writer.WriteUInt32(protocolVersion) Then Return 0
	Return writer.Position()
End Function

Function DecodeQuery:Int(data:Byte Ptr, length:Size_T, gameId:String Var, protocolVersion:UInt Var)
	Local reader:SPacketReader = New SPacketReader(data, length)
	Local magic:UInt, wireVersion:UInt, kind:UInt
	If Not reader.ReadUInt32(magic) Or magic <> LAN_DISCOVERY_MAGIC Or Not reader.ReadUInt8(wireVersion) Or ..
		wireVersion <> LAN_DISCOVERY_PROTOCOL_VERSION Or Not reader.ReadUInt8(kind) Or kind <> LAN_DISCOVERY_QUERY Or ..
		Not ReadUTF8(reader, gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) Or Not reader.ReadUInt32(protocolVersion) Then Return False
	Return reader.Remaining() = 0 And gameId.Length > 0
End Function

Function EncodeResponse:Size_T(buffer:Byte[], advertisement:SLANAdvertisement)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(buffer), Size_T(buffer.Length))
	If Not writer.WriteUInt32(LAN_DISCOVERY_MAGIC) Or Not writer.WriteUInt8(LAN_DISCOVERY_PROTOCOL_VERSION) Or ..
		Not writer.WriteUInt8(LAN_DISCOVERY_RESPONSE) Or Not WriteUTF8(writer, advertisement.gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) Or ..
		Not writer.WriteUInt32(advertisement.protocolVersion) Or Not writer.WriteUInt16(UInt(advertisement.gamePort)) Or ..
		Not writer.WriteUInt8(UInt(advertisement.players)) Or Not writer.WriteUInt8(UInt(advertisement.capacity)) Or ..
		Not writer.WriteUInt32(advertisement.flags) Or Not WriteUTF8(writer, advertisement.name, GAMENET_LAN_MAX_NAME_BYTES) Or ..
		Not WriteUTF8(writer, advertisement.metadata, GAMENET_LAN_MAX_METADATA_BYTES, True) Then Return 0
	Return writer.Position()
End Function

Function DecodeResponse:Int(data:Byte Ptr, length:Size_T, advertisement:SLANAdvertisement Var)
	Local reader:SPacketReader = New SPacketReader(data, length)
	Local magic:UInt, wireVersion:UInt, kind:UInt, gamePort:UInt, players:UInt, capacity:UInt
	If Not reader.ReadUInt32(magic) Or magic <> LAN_DISCOVERY_MAGIC Or Not reader.ReadUInt8(wireVersion) Or ..
		wireVersion <> LAN_DISCOVERY_PROTOCOL_VERSION Or Not reader.ReadUInt8(kind) Or kind <> LAN_DISCOVERY_RESPONSE Or ..
		Not ReadUTF8(reader, advertisement.gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) Or ..
		Not reader.ReadUInt32(advertisement.protocolVersion) Or Not reader.ReadUInt16(gamePort) Or ..
		Not reader.ReadUInt8(players) Or Not reader.ReadUInt8(capacity) Or Not reader.ReadUInt32(advertisement.flags) Or ..
		Not ReadUTF8(reader, advertisement.name, GAMENET_LAN_MAX_NAME_BYTES) Or ..
		Not ReadUTF8(reader, advertisement.metadata, GAMENET_LAN_MAX_METADATA_BYTES, True) Then Return False
	If reader.Remaining() <> 0 Or advertisement.gameId.Length = 0 Or gamePort = 0 Or capacity = 0 Or players > capacity Then Return False
	advertisement.gamePort = Int(gamePort)
	advertisement.players = Int(players)
	advertisement.capacity = Int(capacity)
	Return True
End Function

Public

Rem
bbdoc: Describes a LAN game advertised to compatible browsers.
about: GameId should be a stable application-specific identifier. ProtocolVersion
should change whenever joining clients are no longer wire-compatible. Metadata is
an optional small application-defined string; it is not interpreted by GameNet.
End Rem
Struct SLANAdvertisement
	Field gameId:String
	Field protocolVersion:UInt
	Field name:String
	Field gamePort:Int
	Field players:Int
	Field capacity:Int
	Field flags:UInt
	Field metadata:String

	Method New(gameId:String, protocolVersion:UInt, name:String, gamePort:Int, players:Int, capacity:Int, flags:UInt = 0, metadata:String = "")
		Self.gameId = gameId
		Self.protocolVersion = protocolVersion
		Self.name = name
		Self.gamePort = gamePort
		Self.players = players
		Self.capacity = capacity
		Self.flags = flags
		Self.metadata = metadata
	End Method

	Method IsValid:Int()
		Return gameId.Length > 0 And ValidUTF8Length(gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) And ..
			ValidUTF8Length(name, GAMENET_LAN_MAX_NAME_BYTES) And ValidUTF8Length(metadata, GAMENET_LAN_MAX_METADATA_BYTES) And ..
			gamePort > 0 And gamePort <= 65535 And players >= 0 And capacity > 0 And capacity <= 255 And players <= capacity
	End Method
End Struct

Rem
bbdoc: One currently visible game returned by #TLANDiscoveryBrowser.
about: Address is taken from the UDP datagram source rather than trusted packet
content. Treat all other fields as untrusted display data until the actual game
connection completes its normal GameNet handshake.
End Rem
Type TLANDiscoveredGame
	Private
	Field _address:String
	Field _advertisement:SLANAdvertisement
	Field _lastSeen:UInt

	Public
	Method New(address:String, advertisement:SLANAdvertisement, lastSeen:UInt)
		_address = address
		_advertisement = advertisement
		_lastSeen = lastSeen
	End Method

	Method Refresh(advertisement:SLANAdvertisement, lastSeen:UInt)
		_advertisement = advertisement
		_lastSeen = lastSeen
	End Method

	Method Address:String()
		Return _address
	End Method

	Method Port:Int()
		Return _advertisement.gamePort
	End Method

	Method GameId:String()
		Return _advertisement.gameId
	End Method

	Method ProtocolVersion:UInt()
		Return _advertisement.protocolVersion
	End Method

	Method Name:String()
		Return _advertisement.name
	End Method

	Method Players:Int()
		Return _advertisement.players
	End Method

	Method Capacity:Int()
		Return _advertisement.capacity
	End Method

	Method Flags:UInt()
		Return _advertisement.flags
	End Method

	Method Metadata:String()
		Return _advertisement.metadata
	End Method

	Method LastSeenMillis:UInt()
		Return _lastSeen
	End Method
End Type

Rem
bbdoc: Answers compatible LAN discovery queries for a hosted game.
about: Call #Update regularly while the game is joinable. The advertised game
port is normally the port passed to #TENetTransport.Listen. Only discovery uses
@discoveryPort; gameplay packets continue to use the selected transport.
End Rem
Type TLANDiscoveryHost
	Private
	Field _socket:TSocket
	Field _advertisement:SLANAdvertisement
	Field _discoveryPort:Int
	Field _receiveBuffer:Byte[] = New Byte[LAN_DISCOVERY_PACKET_BYTES]
	Field _sendBuffer:Byte[] = New Byte[LAN_DISCOVERY_PACKET_BYTES]
	Field _lastError:Int
	Field _maxPacketsPerUpdate:Int

	Method New(socket:TSocket, advertisement:SLANAdvertisement, maxPacketsPerUpdate:Int)
		_socket = socket
		_advertisement = advertisement
		_discoveryPort = SocketLocalPort(socket)
		_maxPacketsPerUpdate = maxPacketsPerUpdate
	End Method

	Public
	Rem
	bbdoc: Creates an advertiser, or returns Null when its configuration or socket cannot be opened.
	about: Passing zero for @discoveryPort selects a free port and is primarily useful for tests.
	End Rem
	Function Create:TLANDiscoveryHost(advertisement:SLANAdvertisement, discoveryPort:Int = GAMENET_LAN_DISCOVERY_PORT, maxPacketsPerUpdate:Int = GAMENET_LAN_MAX_PACKETS_PER_UPDATE)
		If Not advertisement.IsValid() Or discoveryPort < 0 Or discoveryPort > 65535 Or maxPacketsPerUpdate < 1 Then Return Null
		Local socket:TSocket = TSocket.CreateUDP(AF_INET_)
		If Not socket Then Return Null
		socket.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, True)
		If Not socket.Bind(discoveryPort, AF_INET_) Then
			socket.Close()
			Return Null
		End If
		Return New TLANDiscoveryHost(socket, advertisement, maxPacketsPerUpdate)
	End Function

	Method IsOpen:Int()
		Return _socket <> Null
	End Method

	Method DiscoveryPort:Int()
		Return _discoveryPort
	End Method

	Method LastSocketError:Int()
		Return _lastError
	End Method

	Method Advertisement:SLANAdvertisement()
		Return _advertisement
	End Method

	Method SetAdvertisement:Int(advertisement:SLANAdvertisement)
		If Not advertisement.IsValid() Then Return False
		_advertisement = advertisement
		Return True
	End Method

	Rem
	bbdoc: Reads pending queries and sends responses without blocking.
	returns: The number of compatible queries answered.
	End Rem
	Method Update:Int()
		If Not _socket Then Return 0
		_lastError = 0
		Local answered:Int
		Local processed:Int
		While processed < _maxPacketsPerUpdate And DatagramReady(_socket)
			processed :+ 1
			Local senderAddress:Int, senderPort:Int
			Local received:Int = recvfrom_(_socket.Socket(), Byte Ptr(_receiveBuffer), _receiveBuffer.Length, 0, senderAddress, senderPort)
			If received <= 0 Then
				_lastError = SocketLastError(_socket)
				Exit
			End If
			Local gameId:String, protocolVersion:UInt
			If Not DecodeQuery(Byte Ptr(_receiveBuffer), Size_T(received), gameId, protocolVersion) Then Continue
			If gameId <> _advertisement.gameId Or protocolVersion <> _advertisement.protocolVersion Then Continue
			Local length:Size_T = EncodeResponse(_sendBuffer, _advertisement)
			If length = 0 Or Not SendDatagram(_socket, _sendBuffer, length, IPv4String(senderAddress), senderPort) Then
				_lastError = SocketLastError(_socket)
				Continue
			End If
			answered :+ 1
		Wend
		Return answered
	End Method

	Method Close()
		If _socket Then _socket.Close()
		_socket = Null
	End Method
End Type

Rem
bbdoc: Finds compatible games advertised on the local IPv4 network.
about: Call #Update regularly. It sends periodic broadcast queries, receives
responses without blocking, updates duplicate results, and removes stale games.
Use #Refresh with a directed broadcast or loopback address when required by a
particular network or test environment.
End Rem
Type TLANDiscoveryBrowser
	Private
	Field _socket:TSocket
	Field _gameId:String
	Field _protocolVersion:UInt
	Field _discoveryPort:Int
	Field _queryIntervalMillis:UInt
	Field _expiryMillis:UInt
	Field _maximumResults:Int
	Field _maxPacketsPerUpdate:Int
	Field _lastQueryAt:UInt
	Field _hasQueried:Int
	Field _receiveBuffer:Byte[] = New Byte[LAN_DISCOVERY_PACKET_BYTES]
	Field _sendBuffer:Byte[] = New Byte[LAN_DISCOVERY_PACKET_BYTES]
	Field _games:TLANDiscoveredGame[] = New TLANDiscoveredGame[0]
	Field _lastError:Int

	Method New(socket:TSocket, gameId:String, protocolVersion:UInt, discoveryPort:Int, queryIntervalMillis:UInt, expiryMillis:UInt, maximumResults:Int, maxPacketsPerUpdate:Int)
		_socket = socket
		_gameId = gameId
		_protocolVersion = protocolVersion
		_discoveryPort = discoveryPort
		_queryIntervalMillis = queryIntervalMillis
		_expiryMillis = expiryMillis
		_maximumResults = maximumResults
		_maxPacketsPerUpdate = maxPacketsPerUpdate
	End Method

	Method Store(address:String, advertisement:SLANAdvertisement, nowMillis:UInt)
		For Local game:TLANDiscoveredGame = EachIn _games
			If game.Address() = address And game.Port() = advertisement.gamePort Then
				game.Refresh(advertisement, nowMillis)
				Return
			End If
		Next
		If _games.Length >= _maximumResults Then Return
		_games :+ [New TLANDiscoveredGame(address, advertisement, nowMillis)]
	End Method

	Method Expire(nowMillis:UInt)
		If _expiryMillis = 0 Or _games.Length = 0 Then Return
		Local retained:Int
		For Local game:TLANDiscoveredGame = EachIn _games
			If nowMillis - game.LastSeenMillis() < _expiryMillis Then retained :+ 1
		Next
		If retained = _games.Length Then Return
		Local games:TLANDiscoveredGame[] = New TLANDiscoveredGame[retained]
		Local index:Int
		For Local game:TLANDiscoveredGame = EachIn _games
			If nowMillis - game.LastSeenMillis() < _expiryMillis Then
				games[index] = game
				index :+ 1
			End If
		Next
		_games = games
	End Method

	Public
	Rem
	bbdoc: Creates a browser, or returns Null when its configuration or socket cannot be opened.
	End Rem
	Function Create:TLANDiscoveryBrowser(gameId:String, protocolVersion:UInt, discoveryPort:Int = GAMENET_LAN_DISCOVERY_PORT, queryIntervalMillis:UInt = GAMENET_LAN_QUERY_INTERVAL_MILLIS, expiryMillis:UInt = GAMENET_LAN_RESULT_EXPIRY_MILLIS, maximumResults:Int = GAMENET_LAN_MAX_RESULTS, maxPacketsPerUpdate:Int = GAMENET_LAN_MAX_PACKETS_PER_UPDATE)
		If gameId.Length = 0 Or Not ValidUTF8Length(gameId, GAMENET_LAN_MAX_GAME_ID_BYTES) Or discoveryPort < 1 Or discoveryPort > 65535 Or maximumResults < 1 Or maxPacketsPerUpdate < 1 Then Return Null
		Local socket:TSocket = TSocket.CreateUDP(AF_INET_)
		If Not socket Then Return Null
		If Not socket.SetSockOpt(SOL_SOCKET, SO_BROADCAST, True) Or Not socket.Bind(0, AF_INET_) Then
			socket.Close()
			Return Null
		End If
		Return New TLANDiscoveryBrowser(socket, gameId, protocolVersion, discoveryPort, queryIntervalMillis, expiryMillis, maximumResults, maxPacketsPerUpdate)
	End Function

	Method IsOpen:Int()
		Return _socket <> Null
	End Method

	Method LastSocketError:Int()
		Return _lastError
	End Method

	Method Count:Int()
		Return _games.Length
	End Method

	Method Game:TLANDiscoveredGame(index:Int)
		If index < 0 Or index >= _games.Length Then Return Null
		Return _games[index]
	End Method

	Method Clear()
		_games = New TLANDiscoveredGame[0]
	End Method

	Rem
	bbdoc: Immediately sends one query to @address.
	returns: True when the complete datagram was sent.
	End Rem
	Method Refresh:Int(address:String = GAMENET_LAN_BROADCAST_ADDRESS)
		If Not _socket Then Return False
		_lastError = 0
		Local length:Size_T = EncodeQuery(_sendBuffer, _gameId, _protocolVersion)
		If length > 0 And SendDatagram(_socket, _sendBuffer, length, address, _discoveryPort) Then Return True
		_lastError = SocketLastError(_socket)
		Return False
	End Method

	Method Update:Int()
		Return UpdateAt(UInt(MilliSecs()))
	End Method

	Rem
	bbdoc: Updates discovery using an explicit wrap-safe millisecond clock.
	returns: The number of compatible response datagrams accepted.
	End Rem
	Method UpdateAt:Int(nowMillis:UInt)
		If Not _socket Then Return 0
		_lastError = 0
		If _queryIntervalMillis > 0 And (Not _hasQueried Or nowMillis - _lastQueryAt >= _queryIntervalMillis) Then
			Refresh()
			_lastQueryAt = nowMillis
			_hasQueried = True
		End If

		Local accepted:Int
		Local processed:Int
		While processed < _maxPacketsPerUpdate And DatagramReady(_socket)
			processed :+ 1
			Local senderAddress:Int, senderPort:Int
			Local received:Int = recvfrom_(_socket.Socket(), Byte Ptr(_receiveBuffer), _receiveBuffer.Length, 0, senderAddress, senderPort)
			If received <= 0 Then
				_lastError = SocketLastError(_socket)
				Exit
			End If
			Local advertisement:SLANAdvertisement
			If Not DecodeResponse(Byte Ptr(_receiveBuffer), Size_T(received), advertisement) Then Continue
			If advertisement.gameId <> _gameId Or advertisement.protocolVersion <> _protocolVersion Then Continue
			Store(IPv4String(senderAddress), advertisement, nowMillis)
			accepted :+ 1
		Wend
		Expire(nowMillis)
		Return accepted
	End Method

	Method Close()
		If _socket Then _socket.Close()
		_socket = Null
		Clear()
	End Method
End Type

?
