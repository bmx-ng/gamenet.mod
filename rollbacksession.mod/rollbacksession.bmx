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
bbdoc: High-level deterministic rollback session orchestration.
End Rem
Module GameNet.RollbackSession

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial rollback session"

Import GameNet.Session
Import GameNet.Rollback
Import BRL.Blitz

Rem
bbdoc: Receives presentation effects produced while simulating one frame.
about: Effects are retained by the rollback session and become visible to the
application only after their frame is confirmed. Payload bytes are copied.
End Rem
Interface IRollbackEffectWriter
	Method Emit:Int(kind:UInt, payload:Byte Ptr = Null, length:Size_T = 0)
End Interface

Rem
bbdoc: One confirmed presentation effect from a deterministic frame.
about: The payload is borrowed and remains valid until the next rollback
session operation.
End Rem
Struct SRollbackEffect
	Private
	Field _frame:UInt
	Field _kind:UInt
	Field _payload:SPacketView

	Method New(frame:UInt, kind:UInt, payload:SPacketView)
		_frame = frame
		_kind = kind
		_payload = payload
	End Method

	Public
	Method New()
	End Method

	Method Frame:UInt()
		Return _frame
	End Method

	Method Kind:UInt()
		Return _kind
	End Method

	Method Payload:SPacketView()
		Return _payload
	End Method
End Struct

Rem
bbdoc: Deterministic game operations used by #TRollbackSession.
about: Implementations should not perform presentation or irreversible effects
directly inside #SimulateFrame because a frame may be simulated more than once.
They may additionally implement #IRollbackEffectSimulation to record such effects
safely. The input array and all packet views are borrowed.
End Rem
Interface IRollbackSimulation
	Rem
	bbdoc: Writes the current deterministic state and returns its byte length.
	End Rem
	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)

	Rem
	bbdoc: Restores deterministic state captured by #SaveState.
	End Rem
	Method LoadState:Int(state:SPacketView)

	Rem
	bbdoc: Writes a prediction for a missing player input.
	about: @previous is the most recent input for that player, or an empty view.
	End Rem
	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)

	Rem
	bbdoc: Advances deterministic game state by exactly one frame.
	End Rem
	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
End Interface

Rem
bbdoc: Optional extended simulation contract for rollback-safe effects.
about: Implement both #SimulateFrame overloads. The rollback session uses the
three-argument overload and retains emitted effects until confirmation.
End Rem
Interface IRollbackEffectSimulation
	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[], effects:IRollbackEffectWriter)
End Interface

Rem
bbdoc: Configuration for a #TRollbackSession.
End Rem
Struct SRollbackSessionConfig
	Field playerCount:Int
	Field localPlayer:Int
	Field historyFrames:Int
	Field maxStateSize:Size_T
	Field maxInputSize:Size_T
	Field inputDelayFrames:Int
	Field maxPredictionFrames:Int
	Field redundantInputFrames:Int
	Field hashInterval:UInt
	Field hashQueueSize:Int
	Field maxEffectsPerFrame:Int
	Field maxEffectSize:Size_T
	Field confirmedEffectCapacity:Int

	Method New(playerCount:Int, localPlayer:Int, historyFrames:Int, maxStateSize:Size_T, maxInputSize:Size_T, inputDelayFrames:Int = 3, maxPredictionFrames:Int = 8, redundantInputFrames:Int = 12, hashInterval:UInt = 30, hashQueueSize:Int = 32, maxEffectsPerFrame:Int = 8, maxEffectSize:Size_T = 64, confirmedEffectCapacity:Int = 64)
		Self.playerCount = playerCount
		Self.localPlayer = localPlayer
		Self.historyFrames = historyFrames
		Self.maxStateSize = maxStateSize
		Self.maxInputSize = maxInputSize
		Self.inputDelayFrames = inputDelayFrames
		Self.maxPredictionFrames = maxPredictionFrames
		Self.redundantInputFrames = redundantInputFrames
		Self.hashInterval = hashInterval
		Self.hashQueueSize = hashQueueSize
		Self.maxEffectsPerFrame = maxEffectsPerFrame
		Self.maxEffectSize = maxEffectSize
		Self.confirmedEffectCapacity = confirmedEffectCapacity
	End Method
End Struct

Rem
bbdoc: Orchestrates a peer's deterministic rollback timeline.
about: The session owns bounded state, input, packet, and hash storage. Normal
frame operations reuse that storage. It does not own or poll the network
session; applications route input and hash messages to #ReceiveInputs and
#ReceiveHash and may use the provided send helpers.
End Rem
Type TRollbackSession Implements IRollbackEffectWriter
	Private
	Field _simulation:IRollbackSimulation
	Field _effectSimulation:IRollbackEffectSimulation
	Field _config:SRollbackSessionConfig
	Field _rollback:TRollbackBuffer
	Field _stateBuffer:Byte Ptr
	Field _inputBuffer:Byte Ptr
	Field _frameInputs:SRollbackInput[]
	Field _priorInputs:SPacketView[]
	Field _running:Int
	Field _failed:Int
	Field _currentFrame:UInt
	Field _totalFrames:Long
	Field _hasRemoteFrame:Int
	Field _remoteSimulationFrame:UInt
	Field _rollbackCount:Int
	Field _lastRollbackDepth:Int
	Field _largestRollbackDepth:Int
	Field _predictedFrames:Int
	Field _matchedPredictions:Int
	Field _mismatchedPredictions:Int
	Field _rejectedInputs:Int
	Field _hashesChecked:Int
	Field _hashMismatches:Int
	Field _hasLastHashSent:Int
	Field _lastHashSent:UInt
	Field _remoteHashValid:Byte[]
	Field _remoteHashFrames:UInt[]
	Field _remoteHashes:UInt[]
	Field _effectFrameTags:UInt[]
	Field _effectFrameValid:Byte[]
	Field _effectFrameCounts:Int[]
	Field _effectKinds:UInt[]
	Field _effectLengths:Size_T[]
	Field _effectStorage:Byte Ptr
	Field _recordingEffects:Int
	Field _recordingEffectSlot:Int
	Field _confirmedEffectFrames:UInt[]
	Field _confirmedEffectKinds:UInt[]
	Field _confirmedEffectLengths:Size_T[]
	Field _confirmedEffectStorage:Byte Ptr
	Field _confirmedEffectRead:Int
	Field _confirmedEffectWrite:Int
	Field _confirmedEffectCount:Int
	Field _droppedConfirmedEffects:Int
	Field _nextEffectFrame:UInt

	Method New(simulation:IRollbackSimulation, config:SRollbackSessionConfig)
		_simulation = simulation
		_effectSimulation = IRollbackEffectSimulation(simulation)
		_config = config
		_rollback = TRollbackBuffer.Create(config.playerCount, config.historyFrames, config.maxStateSize, config.maxInputSize)
		_stateBuffer = MemAlloc(config.maxStateSize)
		_inputBuffer = MemAlloc(config.maxInputSize)
		_frameInputs = New SRollbackInput[config.playerCount]
		_priorInputs = New SPacketView[config.playerCount]
		_remoteHashValid = New Byte[config.hashQueueSize]
		_remoteHashFrames = New UInt[config.hashQueueSize]
		_remoteHashes = New UInt[config.hashQueueSize]
		If _effectSimulation Then
			_effectFrameTags = New UInt[config.historyFrames]
			_effectFrameValid = New Byte[config.historyFrames]
			_effectFrameCounts = New Int[config.historyFrames]
			_effectKinds = New UInt[config.historyFrames * config.maxEffectsPerFrame]
			_effectLengths = New Size_T[config.historyFrames * config.maxEffectsPerFrame]
			_effectStorage = MemAlloc(Size_T(config.historyFrames * config.maxEffectsPerFrame) * config.maxEffectSize)
			_confirmedEffectFrames = New UInt[config.confirmedEffectCapacity]
			_confirmedEffectKinds = New UInt[config.confirmedEffectCapacity]
			_confirmedEffectLengths = New Size_T[config.confirmedEffectCapacity]
			_confirmedEffectStorage = MemAlloc(Size_T(config.confirmedEffectCapacity) * config.maxEffectSize)
		End If
	End Method

	Method SaveCurrentState:Int(frame:UInt)
		Local length:Size_T = _simulation.SaveState(_stateBuffer, _config.maxStateSize)
		If length = 0 Or length > _config.maxStateSize Then Return False
		Return _rollback.SaveState(frame, _stateBuffer, length)
	End Method

	Method FindPriorInput:SPacketView(player:Int, frame:UInt)
		For Local age:Int = 1 Until _rollback.Capacity()
			Local input:SRollbackInput
			If _rollback.GetInput(player, frame - UInt(age), input) Then Return input.Payload()
		Next
		Return New SPacketView
	End Method

	Method EffectEntry:Int(frameSlot:Int, effectIndex:Int)
		Return frameSlot * _config.maxEffectsPerFrame + effectIndex
	End Method

	Method EffectAddress:Byte Ptr(entry:Int)
		Return _effectStorage + Size_T(entry) * _config.maxEffectSize
	End Method

	Method ConfirmedEffectAddress:Byte Ptr(slot:Int)
		Return _confirmedEffectStorage + Size_T(slot) * _config.maxEffectSize
	End Method

	Method BeginEffectFrame(frame:UInt)
		If Not _effectSimulation Then Return
		Local slot:Int = Int(frame Mod UInt(_config.historyFrames))
		_effectFrameTags[slot] = frame
		_effectFrameValid[slot] = True
		_effectFrameCounts[slot] = 0
		_recordingEffectSlot = slot
		_recordingEffects = True
	End Method

	Method EndEffectFrame()
		_recordingEffects = False
	End Method

	Method QueueConfirmedEffect(frame:UInt, kind:UInt, payload:Byte Ptr, length:Size_T)
		If _confirmedEffectCount = _confirmedEffectFrames.Length Then
			_droppedConfirmedEffects :+ 1
			Return
		End If
		Local slot:Int = _confirmedEffectWrite
		_confirmedEffectFrames[slot] = frame
		_confirmedEffectKinds[slot] = kind
		_confirmedEffectLengths[slot] = length
		If length > 0 Then MemCopy(ConfirmedEffectAddress(slot), payload, length)
		_confirmedEffectWrite = (_confirmedEffectWrite + 1) Mod _confirmedEffectFrames.Length
		_confirmedEffectCount :+ 1
	End Method

	Method CommitConfirmedEffects()
		If Not _effectSimulation Or _rollback.NeedsRollback() Or Not _rollback.HasConfirmedFrame() Or _totalFrames = 0 Then Return
		Local confirmed:UInt = _rollback.ConfirmedFrame()
		Local lastSimulated:UInt = _currentFrame - 1
		If RollbackFrameAfter(confirmed, lastSimulated) Then confirmed = lastSimulated
		While Not RollbackFrameAfter(_nextEffectFrame, confirmed)
			Local frameSlot:Int = Int(_nextEffectFrame Mod UInt(_config.historyFrames))
			If _effectFrameValid[frameSlot] And _effectFrameTags[frameSlot] = _nextEffectFrame Then
				For Local effectIndex:Int = 0 Until _effectFrameCounts[frameSlot]
					Local entry:Int = EffectEntry(frameSlot, effectIndex)
					QueueConfirmedEffect(_nextEffectFrame, _effectKinds[entry], EffectAddress(entry), _effectLengths[entry])
				Next
			End If
			_nextEffectFrame :+ 1
		Wend
	End Method

	Method PrepareInputs:Int(frame:UInt, replacePredictions:Int)
		For Local player:Int = 0 Until _config.playerCount
			Local input:SRollbackInput
			Local found:Int = _rollback.GetInput(player, frame, input)
			If player <> _config.localPlayer And (Not found Or (replacePredictions And input.Status() = ERollbackInputStatus.Predicted)) Then
				Local previous:SPacketView = _priorInputs[player]
				If previous.IsEmpty() Then previous = FindPriorInput(player, frame)
				Local length:Size_T = _simulation.PredictInput(player, frame, previous, _inputBuffer, _config.maxInputSize)
				If length = 0 Or length > _config.maxInputSize Or Not _rollback.PredictInput(player, frame, _inputBuffer, length) Then Return False
				If Not _rollback.GetInput(player, frame, input) Then Return False
				If Not replacePredictions Then _predictedFrames :+ 1
			Else If Not found Then
				Return False
			End If
			_frameInputs[player] = input
			_priorInputs[player] = input.Payload()
		Next
		Return True
	End Method

	Method PerformRollback:Int()
		If Not _rollback.NeedsRollback() Then Return True
		Local startFrame:UInt = _rollback.RollbackFrame()
		Local state:SPacketView
		If Not _rollback.GetState(startFrame, state) Or Not _simulation.LoadState(state) Then Return False
		Local depth:Int = RollbackFrameDelta(_currentFrame, startFrame)
		If depth < 0 Or depth >= _rollback.Capacity() Then Return False
		For Local player:Int = 0 Until _config.playerCount
			_priorInputs[player] = FindPriorInput(player, startFrame)
		Next
		For Local offset:Int = 0 Until depth
			Local frame:UInt = startFrame + UInt(offset)
			If Not SaveCurrentState(frame) Or Not PrepareInputs(frame, True) Then Return False
			BeginEffectFrame(frame)
			Local simulated:Int
			If _effectSimulation Then
				simulated = _effectSimulation.SimulateFrame(frame, _frameInputs, Self)
			Else
				simulated = _simulation.SimulateFrame(frame, _frameInputs)
			End If
			EndEffectFrame()
			If Not simulated Then Return False
		Next
		If Not SaveCurrentState(_currentFrame) Then Return False
		_rollback.ClearRollback()
		_rollbackCount :+ 1
		_lastRollbackDepth = depth
		_largestRollbackDepth = Max(_largestRollbackDepth, depth)
		Return True
	End Method

	Method CheckRemoteHashes()
		If _rollback.NeedsRollback() Or Not _rollback.HasConfirmedFrame() Then Return
		Local confirmedStateFrame:UInt = _rollback.ConfirmedFrame() + 1
		For Local slot:Int = 0 Until _remoteHashValid.Length
			If Not _remoteHashValid[slot] Then Continue
			If RollbackFrameAfter(_remoteHashFrames[slot], confirmedStateFrame) Or RollbackFrameAfter(_remoteHashFrames[slot], _currentFrame) Then Continue
			Local localHash:UInt = _rollback.StateHash(_remoteHashFrames[slot])
			If localHash <> 0 Then
				_hashesChecked :+ 1
				If localHash <> _remoteHashes[slot] Then _hashMismatches :+ 1
			End If
			_remoteHashValid[slot] = False
		Next
	End Method

	Function ValidConfig:Int(simulation:IRollbackSimulation, config:SRollbackSessionConfig)
		Return simulation <> Null And config.playerCount = 2 And config.localPlayer >= 0 And config.localPlayer < config.playerCount ..
			And config.historyFrames >= 2 And config.maxStateSize > 0 And config.maxInputSize > 0 ..
			And config.inputDelayFrames >= 0 And config.inputDelayFrames < config.historyFrames ..
			And config.maxPredictionFrames >= 0 And config.maxPredictionFrames < config.historyFrames ..
			And config.redundantInputFrames >= 1 And config.redundantInputFrames <= 255 ..
			And config.hashQueueSize >= 1 And config.maxEffectsPerFrame >= 1 ..
			And config.maxEffectSize >= 1 And config.confirmedEffectCapacity >= 1
	End Function

	Public
	Rem
	bbdoc: Creates a bounded rollback session, or Null for invalid configuration.
	End Rem
	Function Create:TRollbackSession(simulation:IRollbackSimulation, config:SRollbackSessionConfig)
		If Not ValidConfig(simulation, config) Then Return Null
		Return New TRollbackSession(simulation, config)
	End Function

	Method Delete()
		If _stateBuffer Then MemFree(_stateBuffer)
		If _inputBuffer Then MemFree(_inputBuffer)
		If _effectStorage Then MemFree(_effectStorage)
		If _confirmedEffectStorage Then MemFree(_confirmedEffectStorage)
		_stateBuffer = Null
		_inputBuffer = Null
		_effectStorage = Null
		_confirmedEffectStorage = Null
	End Method

	Rem
	bbdoc: Records one effect for the frame currently being simulated.
	returns: False outside simulation or when the per-frame bounds are exceeded.
	End Rem
	Method Emit:Int(kind:UInt, payload:Byte Ptr = Null, length:Size_T = 0) Override
		If Not _recordingEffects Or length > _config.maxEffectSize Or (length > 0 And Not payload) Then Return False
		Local effectIndex:Int = _effectFrameCounts[_recordingEffectSlot]
		If effectIndex >= _config.maxEffectsPerFrame Then Return False
		Local entry:Int = EffectEntry(_recordingEffectSlot, effectIndex)
		_effectKinds[entry] = kind
		_effectLengths[entry] = length
		If length > 0 Then MemCopy(EffectAddress(entry), payload, length)
		_effectFrameCounts[_recordingEffectSlot] = effectIndex + 1
		Return True
	End Method

	Rem
	bbdoc: Returns the next effect whose frame is fully confirmed.
	about: Consume effects regularly. If the bounded delivery queue fills, new
	effects are dropped and counted by #DroppedConfirmedEffects.
	End Rem
	Method PollConfirmedEffect:Int(effect:SRollbackEffect Var)
		If _confirmedEffectCount = 0 Then
			effect = New SRollbackEffect
			Return False
		End If
		Local slot:Int = _confirmedEffectRead
		effect = New SRollbackEffect(_confirmedEffectFrames[slot], _confirmedEffectKinds[slot], New SPacketView(ConfirmedEffectAddress(slot), _confirmedEffectLengths[slot]))
		_confirmedEffectRead = (_confirmedEffectRead + 1) Mod _confirmedEffectFrames.Length
		_confirmedEffectCount :- 1
		Return True
	End Method

	Rem
	bbdoc: Starts at frame zero from the simulation's current state.
	param initialInput: Neutral local input used for the configured delay frames.
	End Rem
	Method Start:Int(initialInput:Byte Ptr, inputLength:Size_T)
		If inputLength = 0 Or inputLength > _config.maxInputSize Or Not initialInput Then Return False
		_rollback.Clear()
		_currentFrame = 0
		_totalFrames = 0
		_running = True
		_failed = False
		_hasRemoteFrame = False
		_remoteSimulationFrame = 0
		_rollbackCount = 0
		_lastRollbackDepth = 0
		_largestRollbackDepth = 0
		_predictedFrames = 0
		_matchedPredictions = 0
		_mismatchedPredictions = 0
		_rejectedInputs = 0
		_hashesChecked = 0
		_hashMismatches = 0
		_hasLastHashSent = False
		_recordingEffects = False
		_confirmedEffectRead = 0
		_confirmedEffectWrite = 0
		_confirmedEffectCount = 0
		_droppedConfirmedEffects = 0
		_nextEffectFrame = 0
		For Local slot:Int = 0 Until _remoteHashValid.Length
			_remoteHashValid[slot] = False
		Next
		For Local slot:Int = 0 Until _effectFrameValid.Length
			_effectFrameValid[slot] = False
		Next
		For Local frame:UInt = 0 Until UInt(_config.inputDelayFrames)
			If _rollback.ConfirmInput(_config.localPlayer, frame, initialInput, inputLength) = ERollbackConfirmResult.Rejected Then Return False
		Next
		If Not SaveCurrentState(0) Then
			_failed = True
			Return False
		End If
		Return True
	End Method

	Method Stop()
		_running = False
		_recordingEffects = False
	End Method

	Rem
	bbdoc: Returns whether another simulation frame may be predicted.
	End Rem
	Method CanStep:Int()
		If Not _running Or _failed Then Return False
		If Not _rollback.HasConfirmedFrame() Then Return _currentFrame <= UInt(_config.maxPredictionFrames)
		Local nextUnconfirmedFrame:UInt = _rollback.ConfirmedFrame() + 1
		Return RollbackFrameDelta(_currentFrame, nextUnconfirmedFrame) <= _config.maxPredictionFrames
	End Method

	Rem
	bbdoc: Schedules local input, resolves rollback, and simulates one frame.
	End Rem
	Method Step:Int(localInput:Byte Ptr, inputLength:Size_T)
		If Not CanStep() Or inputLength = 0 Or inputLength > _config.maxInputSize Or Not localInput Then Return False
		If Not PerformRollback() Or Not SaveCurrentState(_currentFrame) Then
			_failed = True
			Return False
		End If
		Local scheduledFrame:UInt = _currentFrame + UInt(_config.inputDelayFrames)
		If _rollback.ConfirmInput(_config.localPlayer, scheduledFrame, localInput, inputLength) = ERollbackConfirmResult.Rejected Then
			_failed = True
			Return False
		End If
		For Local player:Int = 0 Until _config.playerCount
			_priorInputs[player] = New SPacketView
		Next
		If Not PrepareInputs(_currentFrame, False) Then
			_failed = True
			Return False
		End If
		BeginEffectFrame(_currentFrame)
		Local simulated:Int
		If _effectSimulation Then
			simulated = _effectSimulation.SimulateFrame(_currentFrame, _frameInputs, Self)
		Else
			simulated = _simulation.SimulateFrame(_currentFrame, _frameInputs)
		End If
		EndEffectFrame()
		If Not simulated Then
			_failed = True
			Return False
		End If
		_currentFrame :+ 1
		_totalFrames :+ 1
		If Not SaveCurrentState(_currentFrame) Then
			_failed = True
			Return False
		End If
		CheckRemoteHashes()
		CommitConfirmedEffects()
		Return True
	End Method

	Rem
	bbdoc: Writes a redundant batch of recent local inputs.
	End Rem
	Method WriteInputs:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If Not _running Or Not buffer Then Return 0
		Local available:Long = _totalFrames + Long(_config.inputDelayFrames)
		Local count:Int = _config.redundantInputFrames
		If available < Long(count) Then count = Int(available)
		If count < 1 Then Return 0
		Local newestFrame:UInt = _currentFrame + UInt(_config.inputDelayFrames - 1)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(_currentFrame)
		writer.WriteUInt8(UInt(count))
		For Local age:Int = count - 1 To 0 Step -1
			Local frame:UInt = newestFrame - UInt(age)
			Local input:SRollbackInput
			If Not _rollback.GetInput(_config.localPlayer, frame, input) Or input.Status() <> ERollbackInputStatus.Confirmed Then Return 0
			writer.WriteUInt32(frame)
			writer.WriteUInt16(UInt(input.Payload().Length()))
			writer.WriteBytes(input.Payload().Data(), input.Payload().Length())
		Next
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Rem
	bbdoc: Accepts a batch produced by #WriteInputs for @player.
	End Rem
	Method ReceiveInputs:Int(player:Int, packet:SPacketView)
		If Not _running Or _failed Or player < 0 Or player >= _config.playerCount Or player = _config.localPlayer Then Return False
		Local reader:SPacketReader = New SPacketReader(packet)
		Local simulatedFrame:UInt
		Local count:UInt
		If Not reader.ReadUInt32(simulatedFrame) Or Not reader.ReadUInt8(count) Then Return False
		If count < 1 Or count > UInt(_config.redundantInputFrames) Then Return False
		Local priorFrame:UInt
		For Local index:Int = 0 Until Int(count)
			Local frame:UInt
			Local length:UInt
			If Not reader.ReadUInt32(frame) Or Not reader.ReadUInt16(length) Then Return False
			If length < 1 Or length > UInt(_config.maxInputSize) Or Size_T(length) > reader.Remaining() Then Return False
			If index > 0 And Not RollbackFrameAfter(frame, priorFrame) Then Return False
			If Not reader.Skip(Size_T(length)) Then Return False
			priorFrame = frame
		Next
		If reader.Remaining() <> 0 Then Return False

		' Parse again only after the complete packet has been validated, so a
		' malformed trailing entry cannot partially mutate rollback history.
		reader = New SPacketReader(packet)
		reader.ReadUInt32(simulatedFrame)
		reader.ReadUInt8(count)
		For Local index:Int = 0 Until Int(count)
			Local frame:UInt
			Local length:UInt
			reader.ReadUInt32(frame)
			reader.ReadUInt16(length)
			Local payload:SPacketView = reader.RemainingView()
			Local result:ERollbackConfirmResult = _rollback.ConfirmInput(player, frame, payload.Data(), Size_T(length))
			Select result
				Case ERollbackConfirmResult.PredictionMatched
					_matchedPredictions :+ 1
				Case ERollbackConfirmResult.PredictionMismatched
					_mismatchedPredictions :+ 1
				Case ERollbackConfirmResult.Rejected
					_rejectedInputs :+ 1
			End Select
			If Not reader.Skip(Size_T(length)) Then Return False
		Next
		If Not _hasRemoteFrame Or RollbackFrameAfter(simulatedFrame, _remoteSimulationFrame) Then _remoteSimulationFrame = simulatedFrame
		_hasRemoteFrame = True
		CommitConfirmedEffects()
		Return True
	End Method

	Rem
	bbdoc: Sends recent inputs through a GameNet session.
	End Rem
	Method SendInputs:ETransportResult(session:TNetSession, peer:SNetPeer, messageType:UInt, channel:UInt, packetBuffer:Byte Ptr, packetCapacity:Size_T)
		Local length:Size_T = WriteInputs(packetBuffer, packetCapacity)
		If length = 0 Then Return ETransportResult.Failed
		Return session.Send(peer, messageType, channel, EDeliveryMode.UnreliableSequenced, packetBuffer, length)
	End Method

	Rem
	bbdoc: Writes the next confirmed state hash, or zero when none is ready.
	End Rem
	Method WriteReadyHash:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If Not _running Or Not buffer Or _config.hashInterval = 0 Or Not _rollback.HasConfirmedFrame() Then Return 0
		Local confirmedStateFrame:UInt = _rollback.ConfirmedFrame() + 1
		Local frame:UInt = (confirmedStateFrame / _config.hashInterval) * _config.hashInterval
		If frame = 0 Or RollbackFrameAfter(frame, _currentFrame) Then Return 0
		If _hasLastHashSent And Not RollbackFrameAfter(frame, _lastHashSent) Then Return 0
		Local hash:UInt = _rollback.StateHash(frame)
		If hash = 0 Then Return 0
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(frame)
		writer.WriteUInt32(hash)
		If writer.Failed() Then Return 0
		_hasLastHashSent = True
		_lastHashSent = frame
		Return writer.Position()
	End Method

	Rem
	bbdoc: Accepts a confirmed state hash produced by #WriteReadyHash.
	End Rem
	Method ReceiveHash:Int(packet:SPacketView)
		If Not _running Or _failed Then Return False
		Local reader:SPacketReader = New SPacketReader(packet)
		Local frame:UInt
		Local hash:UInt
		If Not reader.ReadUInt32(frame) Or Not reader.ReadUInt32(hash) Or reader.Remaining() <> 0 Then Return False
		Local slot:Int = Int(frame Mod UInt(_remoteHashValid.Length))
		_remoteHashValid[slot] = True
		_remoteHashFrames[slot] = frame
		_remoteHashes[slot] = hash
		CheckRemoteHashes()
		Return True
	End Method

	Rem
	bbdoc: Sends the next ready confirmed-state hash.
	End Rem
	Method SendReadyHash:ETransportResult(session:TNetSession, peer:SNetPeer, messageType:UInt, channel:UInt, packetBuffer:Byte Ptr, packetCapacity:Size_T)
		Local priorHasLast:Int = _hasLastHashSent
		Local priorLast:UInt = _lastHashSent
		Local length:Size_T = WriteReadyHash(packetBuffer, packetCapacity)
		If length = 0 Then Return ETransportResult.WouldBlock
		Local result:ETransportResult = session.Send(peer, messageType, channel, EDeliveryMode.ReliableOrdered, packetBuffer, length)
		If result <> ETransportResult.Ok Then
			_hasLastHashSent = priorHasLast
			_lastHashSent = priorLast
		End If
		Return result
	End Method

	Method IsRunning:Int()
		Return _running
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method CurrentFrame:UInt()
		Return _currentFrame
	End Method

	Method HasRemoteFrame:Int()
		Return _hasRemoteFrame
	End Method

	Method RemoteSimulationFrame:UInt()
		Return _remoteSimulationFrame
	End Method

	Method HasConfirmedFrame:Int()
		Return _rollback.HasConfirmedFrame()
	End Method

	Method ConfirmedFrame:UInt()
		Return _rollback.ConfirmedFrame()
	End Method

	Method RollbackCount:Int()
		Return _rollbackCount
	End Method

	Method LastRollbackDepth:Int()
		Return _lastRollbackDepth
	End Method

	Method LargestRollbackDepth:Int()
		Return _largestRollbackDepth
	End Method

	Method PredictedFrames:Int()
		Return _predictedFrames
	End Method

	Method PredictionMatches:Int()
		Return _matchedPredictions
	End Method

	Method PredictionMismatches:Int()
		Return _mismatchedPredictions
	End Method

	Method RejectedInputs:Int()
		Return _rejectedInputs
	End Method

	Method HashesChecked:Int()
		Return _hashesChecked
	End Method

	Method HashMismatches:Int()
		Return _hashMismatches
	End Method

	Method PendingConfirmedEffects:Int()
		Return _confirmedEffectCount
	End Method

	Method DroppedConfirmedEffects:Int()
		Return _droppedConfirmedEffects
	End Method
End Type

?
