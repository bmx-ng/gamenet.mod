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
bbdoc: Bounded snapshot history, server-clock estimation, and jitter delay.
End Rem
Module GameNet.Snapshot

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial snapshot timeline and timing helpers"

Import GameNet.Core
Import BRL.Blitz

Rem
bbdoc: Returns the signed modular distance from @reference to @tick.
about: The result is valid when the two ticks are less than 2^31 ticks apart.
This makes comparisons continue to work when a 32-bit tick counter wraps.
End Rem
Function SnapshotTickDelta:Int(tick:UInt, reference:UInt)
	Return Int(tick - reference)
End Function

Rem
bbdoc: Returns True when @tick is newer than @reference.
End Rem
Function SnapshotTickAfter:Int(tick:UInt, reference:UInt)
	Return SnapshotTickDelta(tick, reference) > 0
End Function

Rem
bbdoc: A borrowed pair of snapshot states surrounding one render time.
about: When #IsInterpolated is False, both views identify the same endpoint
state and #Blend is zero. Views remain valid until their timeline is changed.
End Rem
Struct SSnapshotSample
	Private
	Field _fromTick:UInt
	Field _toTick:UInt
	Field _fromState:SPacketView
	Field _toState:SPacketView
	Field _blend:Float

	Method New(fromTick:UInt, toTick:UInt, fromState:SPacketView, toState:SPacketView, blend:Float)
		_fromTick = fromTick
		_toTick = toTick
		_fromState = fromState
		_toState = toState
		_blend = blend
	End Method

	Public
	Method New()
	End Method

	Rem
	bbdoc: Returns the earlier state's wire tick.
	End Rem
	Method FromTick:UInt()
		Return _fromTick
	End Method

	Rem
	bbdoc: Returns the later state's wire tick.
	End Rem
	Method ToTick:UInt()
		Return _toTick
	End Method

	Rem
	bbdoc: Returns a borrowed view of the earlier opaque state.
	End Rem
	Method FromState:SPacketView()
		Return _fromState
	End Method

	Rem
	bbdoc: Returns a borrowed view of the later opaque state.
	End Rem
	Method ToState:SPacketView()
		Return _toState
	End Method

	Rem
	bbdoc: Returns the interpolation factor from the earlier to later state.
	End Rem
	Method Blend:Float()
		Return _blend
	End Method

	Rem
	bbdoc: Returns True when the sample lies between two distinct states.
	End Rem
	Method IsInterpolated:Int()
		Return _fromTick <> _toTick
	End Method
End Struct

Rem
bbdoc: A fixed-capacity timeline of opaque snapshot states.
about: Storage is allocated by #Create. Adding and sampling within the
configured bounds perform no managed allocation. Ticks must arrive in order;
adding the current newest tick replaces its state, while older ticks are
rejected. Sampling clamps to the oldest or newest state instead of
extrapolating.
End Rem
Type TSnapshotTimeline
	Private
	Field _wireTicks:UInt[]
	Field _ticks:Long[]
	Field _lengths:Size_T[]
	Field _storage:Byte Ptr
	Field _maxStateSize:Size_T
	Field _writeIndex:Int
	Field _count:Int
	Field _latestWireTick:UInt
	Field _latestTick:Long

	Method New(capacity:Int, maxStateSize:Size_T)
		_wireTicks = New UInt[capacity]
		_ticks = New Long[capacity]
		_lengths = New Size_T[capacity]
		_maxStateSize = maxStateSize
		_storage = MemAlloc(Size_T(capacity) * maxStateSize)
	End Method

	Method StateView:SPacketView(index:Int)
		Return New SPacketView(_storage + Size_T(index) * _maxStateSize, _lengths[index])
	End Method

	Method SetSlot(index:Int, wireTick:UInt, unwrappedTick:Long, state:Byte Ptr, length:Size_T)
		_wireTicks[index] = wireTick
		_ticks[index] = unwrappedTick
		_lengths[index] = length
		If length > 0 Then MemCopy(_storage + Size_T(index) * _maxStateSize, state, length)
	End Method

	Method EndpointSample:SSnapshotSample(index:Int)
		Local state:SPacketView = StateView(index)
		Return New SSnapshotSample(_wireTicks[index], _wireTicks[index], state, state, 0.0)
	End Method

	Public
	Method Delete()
		If _storage Then MemFree(_storage)
		_storage = Null
	End Method

	Rem
	bbdoc: Creates a timeline with bounded state storage.
	returns: A new timeline, or Null when either argument is less than one.
	End Rem
	Function Create:TSnapshotTimeline(capacity:Int, maxStateSize:Size_T)
		If capacity < 1 Or maxStateSize < 1 Then Return Null
		Return New TSnapshotTimeline(capacity, maxStateSize)
	End Function

	Rem
	bbdoc: Removes every stored snapshot without reallocating storage.
	End Rem
	Method Clear()
		_writeIndex = 0
		_count = 0
		_latestWireTick = 0
		_latestTick = 0
	End Method

	Rem
	bbdoc: Adds an opaque state at @tick.
	returns: False for an oversized state, a non-null length with null data, or
	an older tick. Adding the newest tick again replaces that snapshot.
	End Rem
	Method Add:Int(tick:UInt, state:Byte Ptr, length:Size_T)
		If length > _maxStateSize Or (length > 0 And Not state) Then Return False

		Local unwrappedTick:Long
		If _count > 0 Then
			Local delta:Int = SnapshotTickDelta(tick, _latestWireTick)
			If delta < 0 Then Return False
			If delta = 0 Then
				Local latestIndex:Int = (_writeIndex - 1 + _wireTicks.Length) Mod _wireTicks.Length
				SetSlot(latestIndex, tick, _latestTick, state, length)
				Return True
			End If
			unwrappedTick = _latestTick + Long(delta)
		Else
			unwrappedTick = Long(tick)
		End If

		SetSlot(_writeIndex, tick, unwrappedTick, state, length)
		_writeIndex = (_writeIndex + 1) Mod _wireTicks.Length
		If _count < _wireTicks.Length Then _count :+ 1
		_latestWireTick = tick
		_latestTick = unwrappedTick
		Return True
	End Method

	Rem
	bbdoc: Samples the timeline at an unwrapped server tick.
	about: #LatestUnwrappedTick supplies the same coordinate space. The returned
	views remain valid only until the timeline is changed.
	End Rem
	Method Sample:Int(renderTick:Double, sample:SSnapshotSample Var)
		If _count = 0 Then
			sample = New SSnapshotSample
			Return False
		End If

		Local oldest:Int = (_writeIndex - _count + _wireTicks.Length) Mod _wireTicks.Length
		If renderTick <= Double(_ticks[oldest]) Then
			sample = EndpointSample(oldest)
			Return True
		End If

		Local previousIndex:Int = oldest
		For Local offset:Int = 1 Until _count
			Local currentIndex:Int = (oldest + offset) Mod _wireTicks.Length
			Local currentTick:Double = Double(_ticks[currentIndex])
			If renderTick <= currentTick Then
				If renderTick = currentTick Then
					sample = EndpointSample(currentIndex)
					Return True
				End If
				Local previousTick:Double = Double(_ticks[previousIndex])
				Local span:Double = currentTick - previousTick
				Local blend:Float
				If span > 0.0 Then blend = Float(Max(0.0, Min(1.0, (renderTick - previousTick) / span)))
				sample = New SSnapshotSample(_wireTicks[previousIndex], _wireTicks[currentIndex], StateView(previousIndex), StateView(currentIndex), blend)
				Return True
			End If
			previousIndex = currentIndex
		Next

		sample = EndpointSample(previousIndex)
		Return True
	End Method

	Rem
	bbdoc: Returns the number of stored snapshots.
	End Rem
	Method Count:Int()
		Return _count
	End Method

	Rem
	bbdoc: Returns the maximum number of stored snapshots.
	End Rem
	Method Capacity:Int()
		Return _wireTicks.Length
	End Method

	Rem
	bbdoc: Returns the maximum opaque state size in bytes.
	End Rem
	Method MaxStateSize:Size_T()
		Return _maxStateSize
	End Method

	Rem
	bbdoc: Returns the newest wire tick, or zero when empty.
	End Rem
	Method LatestTick:UInt()
		Return _latestWireTick
	End Method

	Rem
	bbdoc: Returns the newest tick extended across 32-bit wrap-around.
	End Rem
	Method LatestUnwrappedTick:Long()
		Return _latestTick
	End Method
End Type

Rem
bbdoc: Estimates the current server tick from observed snapshots.
about: Observe snapshots with a local monotonic millisecond timestamp. The
clock advances at the configured tick rate between observations. Older or
duplicate ticks do not move the observation anchor.
End Rem
Type TSnapshotClock
	Private
	Field _ticksPerSecond:Double
	Field _observed:Int
	Field _wireTick:UInt
	Field _tick:Long
	Field _localMillis:Int

	Method New(ticksPerSecond:Double)
		_ticksPerSecond = ticksPerSecond
	End Method

	Public
	Rem
	bbdoc: Creates a clock for the server's fixed tick rate.
	End Rem
	Function Create:TSnapshotClock(ticksPerSecond:Double)
		If ticksPerSecond <= 0.0 Then Return Null
		Return New TSnapshotClock(ticksPerSecond)
	End Function

	Rem
	bbdoc: Clears the current clock observation.
	End Rem
	Method Clear()
		_observed = False
		_wireTick = 0
		_tick = 0
		_localMillis = 0
	End Method

	Rem
	bbdoc: Observes a server @tick at local monotonic time @localMillis.
	returns: True when this establishes or advances the clock anchor.
	End Rem
	Method Observe:Int(tick:UInt, localMillis:Int)
		If Not _observed Then
			_observed = True
			_wireTick = tick
			_tick = Long(tick)
			_localMillis = localMillis
			Return True
		End If
		Local delta:Int = SnapshotTickDelta(tick, _wireTick)
		If delta <= 0 Then Return False
		_tick :+ Long(delta)
		_wireTick = tick
		_localMillis = localMillis
		Return True
	End Method

	Rem
	bbdoc: Returns the estimated unwrapped server tick at @localMillis.
	End Rem
	Method Estimate:Double(localMillis:Int)
		If Not _observed Then Return 0.0
		Local elapsed:Int = Int(localMillis - _localMillis)
		If elapsed < 0 Then elapsed = 0
		Return Double(_tick) + Double(elapsed) * _ticksPerSecond / 1000.0
	End Method

	Rem
	bbdoc: Returns True after the first observation.
	End Rem
	Method IsObserved:Int()
		Return _observed
	End Method

	Rem
	bbdoc: Returns the configured server tick rate.
	End Rem
	Method TicksPerSecond:Double()
		Return _ticksPerSecond
	End Method
End Type

Rem
bbdoc: Maintains an optional adaptive snapshot render delay.
about: Delay rises immediately when an arrival is later than its server-tick
spacing predicts, then recovers toward the base delay at a configured rate.
End Rem
Type TSnapshotDelay
	Private
	Field _ticksPerSecond:Double
	Field _baseTicks:Float
	Field _maximumTicks:Float
	Field _safetyTicks:Float
	Field _recoveryTicksPerSecond:Float
	Field _delayTicks:Float
	Field _observed:Int
	Field _lastTick:UInt
	Field _lastArrivalMillis:Int

	Method New(ticksPerSecond:Double, baseTicks:Float, maximumTicks:Float, safetyTicks:Float, recoveryTicksPerSecond:Float)
		_ticksPerSecond = ticksPerSecond
		_baseTicks = baseTicks
		_maximumTicks = maximumTicks
		_safetyTicks = safetyTicks
		_recoveryTicksPerSecond = recoveryTicksPerSecond
		_delayTicks = baseTicks
	End Method

	Public
	Rem
	bbdoc: Creates an adaptive render-delay controller.
	End Rem
	Function Create:TSnapshotDelay(ticksPerSecond:Double, baseTicks:Float, maximumTicks:Float, safetyTicks:Float = 1.0, recoveryTicksPerSecond:Float = 0.5)
		If ticksPerSecond <= 0.0 Or baseTicks < 0.0 Or maximumTicks < baseTicks Or safetyTicks < 0.0 Or recoveryTicksPerSecond < 0.0 Then Return Null
		Return New TSnapshotDelay(ticksPerSecond, baseTicks, maximumTicks, safetyTicks, recoveryTicksPerSecond)
	End Function

	Rem
	bbdoc: Resets the current delay to its configured base.
	End Rem
	Method Clear()
		_delayTicks = _baseTicks
		_observed = False
		_lastTick = 0
		_lastArrivalMillis = 0
	End Method

	Rem
	bbdoc: Updates the delay from one snapshot arrival.
	End Rem
	Method Observe(tick:UInt, arrivalMillis:Int)
		If Not _observed Then
			_observed = True
			_lastTick = tick
			_lastArrivalMillis = arrivalMillis
			Return
		End If

		Local tickDelta:Int = SnapshotTickDelta(tick, _lastTick)
		If tickDelta <= 0 Then Return
		Local arrivalDelta:Int = Int(arrivalMillis - _lastArrivalMillis)
		If arrivalDelta < 0 Then arrivalDelta = 0
		Local arrivalTicks:Double = Double(arrivalDelta) * _ticksPerSecond / 1000.0
		Local lateTicks:Double = Max(0.0, arrivalTicks - Double(tickDelta))
		Local required:Float = _baseTicks
		If lateTicks > 0.0 Then required = Min(_maximumTicks, _baseTicks + _safetyTicks + Float(lateTicks))
		If required > _delayTicks Then
			_delayTicks = required
		Else If _delayTicks > _baseTicks And _recoveryTicksPerSecond > 0.0 Then
			_delayTicks = Max(_baseTicks, _delayTicks - _recoveryTicksPerSecond * Float(arrivalDelta) / 1000.0)
		End If

		_lastTick = tick
		_lastArrivalMillis = arrivalMillis
	End Method

	Rem
	bbdoc: Returns the current render delay in server ticks.
	End Rem
	Method DelayTicks:Float()
		Return _delayTicks
	End Method

	Rem
	bbdoc: Returns the current render delay in milliseconds.
	End Rem
	Method DelayMillis:Float()
		Return _delayTicks * 1000.0 / Float(_ticksPerSecond)
	End Method
End Type

?
