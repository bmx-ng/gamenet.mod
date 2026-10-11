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
'    claim that you wrote the original software.
' 2. Altered source versions must be plainly marked as such.
' 3. This notice may not be removed or altered from any source distribution.

SuperStrict

Rem
bbdoc: Steam Networking Messages transport for GameNet.
End Rem
Module GameNet.Steam

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial Steam Networking Messages transport"

?Not android And Not ios

Import GameNet.Core
Import Steam.SteamSDK

Const STEAM_DEFAULT_MAX_PACKET_SIZE:Size_T = 1200
Const STEAM_FRAME_HEADER_SIZE:Size_T = 10
Const STEAM_FRAME_MAGIC:UInt = $474E5354 ' GNST
Const STEAM_FRAME_VERSION:UInt = 1

Enum ESteamTransportError:Int
	InvalidFrame = 1
	IncomingPacketTooLarge = 2
	UnknownPeer = 3
	SessionFailed = 4
End Enum

Rem
bbdoc: Adapts Steam Networking Messages to #INetTransport.
about: Remote Steam identities are fixed when the transport is created. The
transport adds a small frame header to preserve GameNet delivery modes and
implements stale-packet rejection for unreliable-sequenced messages.
End Rem
Type TSteamTransport Implements INetTransport, ISteamNetworkingMessagesListener
	Private
	Field _network:TSteamNetworkingMessages
	Field _steamIds:ULong[]
	Field _active:Byte[]
	Field _pendingDisconnect:Byte[]
	Field _pendingDisconnectCode:Int[]
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _wireCapacity:Size_T
	Field _receiveBuffer:Byte Ptr
	Field _sendBuffer:Byte Ptr
	Field _sendSequence:UInt[]
	Field _receiveSequence:UInt[]
	Field _receiveSequenceSeen:Byte[]
	Field _connectIndex:Int
	Field _open:Int = True
	Field _failurePeer:Int = -1
	Field _failureCode:Int

	Method New(network:TSteamNetworkingMessages, steamIds:ULong[], channelCount:Int, maxPacketSize:Size_T)
		_network = network
		_steamIds = steamIds[..]
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_wireCapacity = maxPacketSize + STEAM_FRAME_HEADER_SIZE
		_receiveBuffer = MemAlloc(_wireCapacity)
		_sendBuffer = MemAlloc(_wireCapacity)
		_active = New Byte[steamIds.Length]
		_pendingDisconnect = New Byte[steamIds.Length]
		_pendingDisconnectCode = New Int[steamIds.Length]
		_sendSequence = New UInt[channelCount]
		_receiveSequence = New UInt[steamIds.Length * channelCount]
		_receiveSequenceSeen = New Byte[steamIds.Length * channelCount]
		For Local index:Int = 0 Until steamIds.Length
			_active[index] = True
		Next
		_network.SetListener(Self)
	End Method

	Method PeerForIndex:SNetPeer(index:Int)
		Return New SNetPeer(UInt(index + 1), 1)
	End Method

	Method PeerIndex:Int(peer:SNetPeer)
		If Not peer.IsValid() Or peer.Generation() <> 1 Or peer.Id() < 1 Or peer.Id() > UInt(_steamIds.Length) Then Return -1
		Return Int(peer.Id()) - 1
	End Method

	Method PeerIndexForSteamId:Int(steamId:ULong)
		For Local index:Int = 0 Until _steamIds.Length
			If _steamIds[index] = steamId Then Return index
		Next
		Return -1
	End Method

	Method SequenceIndex:Int(peerIndex:Int, channel:UInt)
		Return peerIndex * _channelCount + Int(channel)
	End Method

	Method NextPendingDisconnect:Int()
		For Local index:Int = 0 Until _pendingDisconnect.Length
			If _pendingDisconnect[index] Then Return index
		Next
		Return -1
	End Method

	Public
	Method Delete()
		Close()
		If _receiveBuffer Then MemFree(_receiveBuffer)
		If _sendBuffer Then MemFree(_sendBuffer)
		_receiveBuffer = Null
		_sendBuffer = Null
	End Method

	Function Create:TSteamTransport(steamIds:ULong[], channelCount:Int = 4, maxPacketSize:Size_T = STEAM_DEFAULT_MAX_PACKET_SIZE, network:TSteamNetworkingMessages = Null)
		If Not steamIds Or steamIds.Length = 0 Or channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Or maxPacketSize > Size_T($FFFFFFFF) - STEAM_FRAME_HEADER_SIZE Then Return Null
		For Local steamId:ULong = EachIn steamIds
			If steamId = 0 Then Return Null
		Next
		If Not network Then network = TSteamNetworkingMessages.Create()
		If Not network Then Return Null
		Return New TSteamTransport(network, steamIds, channelCount, maxPacketSize)
	End Function

	Method SteamId:ULong(peer:SNetPeer)
		Local index:Int = PeerIndex(peer)
		If index < 0 Then Return 0
		Return _steamIds[index]
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		SteamRunCallbacks()
		While _connectIndex < _steamIds.Length
			Local index:Int = _connectIndex
			_connectIndex :+ 1
			If _active[index] Then
				event = SNetEvent.Connected(PeerForIndex(index))
				Return True
			End If
		Wend

		Local disconnectIndex:Int = NextPendingDisconnect()
		If disconnectIndex >= 0 Then
			_pendingDisconnect[disconnectIndex] = False
			event = SNetEvent.Disconnected(PeerForIndex(disconnectIndex), _pendingDisconnectCode[disconnectIndex])
			Return True
		End If

		If _failurePeer >= 0 Then
			Local failed:Int = _failurePeer
			_failurePeer = -1
			event = SNetEvent.Error(PeerForIndex(failed), _failureCode)
			Return True
		End If

		If Not _open Then
			event = New SNetEvent
			Return False
		End If

		For Local channel:Int = 0 Until _channelCount
			Local wireLength:UInt
			Local steamId:ULong
			Local reliable:Int
			Local received:Int = _network.ReceiveMessage(channel, _receiveBuffer, UInt(_wireCapacity), wireLength, steamId, reliable)
			If received = 0 Then Continue
			Local peerIndex:Int = PeerIndexForSteamId(steamId)
			If peerIndex < 0 Or Not _active[peerIndex] Then
				event = SNetEvent.Error(New SNetPeer, Int(ESteamTransportError.UnknownPeer))
				Return True
			End If
			If received < 0 Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(ESteamTransportError.IncomingPacketTooLarge))
				Return True
			End If
			Local reader:SPacketReader = New SPacketReader(_receiveBuffer, Size_T(wireLength))
			Local magic:UInt
			Local version:UInt
			Local deliveryValue:UInt
			Local sequence:UInt
			reader.ReadUInt32(magic)
			reader.ReadUInt8(version)
			reader.ReadUInt8(deliveryValue)
			reader.ReadUInt32(sequence)
			If reader.Failed() Or magic <> STEAM_FRAME_MAGIC Or version <> STEAM_FRAME_VERSION Or deliveryValue > UInt(EDeliveryMode.ReliableOrdered) Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(ESteamTransportError.InvalidFrame))
				Return True
			End If
			Local delivery:EDeliveryMode = EDeliveryMode(deliveryValue)
			If delivery = EDeliveryMode.UnreliableSequenced Then
				Local sequenceIndex:Int = SequenceIndex(peerIndex, UInt(channel))
				If _receiveSequenceSeen[sequenceIndex] And Int(sequence - _receiveSequence[sequenceIndex]) <= 0 Then Continue
				_receiveSequenceSeen[sequenceIndex] = True
				_receiveSequence[sequenceIndex] = sequence
			End If
			event = SNetEvent.Data(PeerForIndex(peerIndex), UInt(channel), delivery, New SPacketView(_receiveBuffer + STEAM_FRAME_HEADER_SIZE, Size_T(wireLength) - STEAM_FRAME_HEADER_SIZE))
			Return True
		Next
		event = New SNetEvent
		Return False
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _open Then Return ETransportResult.Closed
		Local peerIndex:Int = PeerIndex(peer)
		If peerIndex < 0 Or Not _active[peerIndex] Then Return ETransportResult.InvalidPeer
		If channel >= UInt(_channelCount) Then Return ETransportResult.InvalidChannel
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local sequence:UInt
		If delivery = EDeliveryMode.UnreliableSequenced Then
			_sendSequence[Int(channel)] :+ 1
			sequence = _sendSequence[Int(channel)]
		End If
		Local writer:SPacketWriter = New SPacketWriter(_sendBuffer, _wireCapacity)
		writer.WriteUInt32(STEAM_FRAME_MAGIC)
		writer.WriteUInt8(STEAM_FRAME_VERSION)
		writer.WriteUInt8(UInt(delivery))
		writer.WriteUInt32(sequence)
		writer.WriteBytes(data, length)
		If writer.Failed() Then Return ETransportResult.PacketTooLarge
		Local flags:Int = STEAM_NETWORKING_SEND_UNRELIABLE
		If delivery = EDeliveryMode.ReliableOrdered Then flags = STEAM_NETWORKING_SEND_RELIABLE
		Local result:EResult = _network.SendMessageToUser(_steamIds[peerIndex], _sendBuffer, UInt(writer.Position()), flags, Int(channel))
		If result <> EResult.k_EResultOK Then Return ETransportResult.Failed
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		Local index:Int = PeerIndex(peer)
		If index < 0 Or Not _active[index] Then Return ETransportResult.InvalidPeer
		_network.CloseSessionWithUser(_steamIds[index])
		_active[index] = False
		_pendingDisconnect[index] = True
		_pendingDisconnectCode[index] = code
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override Return _maxPacketSize End Method
	Method IsOpen:Int() Override Return _open Or NextPendingDisconnect() >= 0 End Method

	Method Close() Override
		If Not _open Then Return
		_open = False
		If _network Then
			_network.SetListener(Null)
			For Local index:Int = 0 Until _steamIds.Length
				If _active[index] Then _network.CloseSessionWithUser(_steamIds[index])
				_active[index] = False
			Next
		End If
	End Method

	Method OnSteamNetworkingMessagesSessionRequest(steamIDRemote:ULong) Override
		Local index:Int = PeerIndexForSteamId(steamIDRemote)
		If _open And index >= 0 And _active[index] Then _network.AcceptSessionWithUser(steamIDRemote)
	End Method

	Method OnSteamNetworkingMessagesSessionFailed(steamIDRemote:ULong, state:ESteamNetworkingConnectionState, endReason:Int, debugMessage:String) Override
		Local index:Int = PeerIndexForSteamId(steamIDRemote)
		If index < 0 Then Return
		_active[index] = False
		_failurePeer = index
		_failureCode = endReason
		_pendingDisconnect[index] = True
		_pendingDisconnectCode[index] = endReason
	End Method
End Type

?
