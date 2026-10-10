SuperStrict

Framework BRL.StandardIO
Import GameNet.Snapshot

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function CheckNear(actual:Double, expected:Double, tolerance:Double, message:String)
	If Abs(actual - expected) > tolerance Then Throw message + ": got " + actual + ", expected " + expected
End Function

Function StateValue:Int(view:SPacketView)
	If view.Length() <> 1 Then Throw "invalid state view"
	Return UInt(view.Data()[0]) & $ff:UInt
End Function

Check(SnapshotTickDelta(5, 3) = 2, "forward tick delta")
Check(SnapshotTickDelta(1, $ffffffff:UInt) = 2, "wrapped tick delta")
Check(SnapshotTickAfter(1, $ffffffff:UInt), "wrapped tick ordering")
Check(Not SnapshotTickAfter(9, 9), "equal tick ordering")

Check(TSnapshotTimeline.Create(0, 1) = Null, "reject zero timeline capacity")
Check(TSnapshotTimeline.Create(2, Size_T(-1)) = Null, "reject snapshot storage overflow")
Local timeline:TSnapshotTimeline = TSnapshotTimeline.Create(3, 2)
Check(timeline <> Null, "create timeline")
Local sample:SSnapshotSample
Check(Not timeline.Sample(0.0, sample), "empty timeline cannot sample")

Local states:Byte[5]
states[0] = 10
states[1] = 20
states[2] = 30
states[3] = 40
states[4] = 50
Check(timeline.Add(10, Byte Ptr(states) + 0, 1), "add first snapshot")
Check(timeline.Add(12, Byte Ptr(states) + 1, 1), "add second snapshot")
Check(timeline.Add(14, Byte Ptr(states) + 2, 1), "add third snapshot")
Check(timeline.Count() = 3 And timeline.LatestTick() = 14, "timeline metadata")

Check(timeline.Sample(9.0, sample), "sample before history")
Check(StateValue(sample.FromState()) = 10 And Not sample.IsInterpolated(), "clamp to oldest")
Check(timeline.Sample(11.0, sample), "sample between states")
Check(StateValue(sample.FromState()) = 10 And StateValue(sample.ToState()) = 20, "surrounding states")
CheckNear(sample.Blend(), 0.5, 0.0001, "interpolation blend")
Check(timeline.Sample(20.0, sample), "sample after history")
Check(StateValue(sample.FromState()) = 30 And Not sample.IsInterpolated(), "clamp to newest")

Check(timeline.Add(14, Byte Ptr(states) + 3, 1), "replace newest snapshot")
Check(timeline.Count() = 3, "replacement does not grow timeline")
Check(timeline.Sample(14.0, sample) And StateValue(sample.FromState()) = 40, "replacement state")
Check(Not timeline.Add(13, Byte Ptr(states), 1), "reject older snapshot")
Check(Not timeline.Add(15, Byte Ptr(states), 3), "reject oversized state")

Check(timeline.Add(16, Byte Ptr(states) + 4, 1), "overwrite oldest snapshot")
Check(timeline.Sample(10.0, sample) And StateValue(sample.FromState()) = 20, "bounded history overwrites oldest")

timeline.Clear()
Check(timeline.Count() = 0 And Not timeline.Sample(0.0, sample), "clear timeline")
Check(timeline.Add($fffffffe:UInt, Byte Ptr(states), 1), "add near wrap")
Check(timeline.Add(1, Byte Ptr(states) + 1, 1), "add after wrap")
Check(timeline.LatestUnwrappedTick() = Long($fffffffe:UInt) + 3, "unwrap ticks")
Check(timeline.Sample(Double(timeline.LatestUnwrappedTick()) - 1.5, sample), "sample across wrap")
CheckNear(sample.Blend(), 0.5, 0.0001, "wrapped interpolation blend")

Local clock:TSnapshotClock = TSnapshotClock.Create(60.0)
Check(clock <> Null And Not clock.IsObserved(), "create clock")
Check(clock.Observe($ffffffff:UInt, 1000), "first clock observation")
CheckNear(clock.Estimate(1050), Double($ffffffff:UInt) + 3.0, 0.0001, "clock advances locally")
Check(clock.Observe(1, 1100), "clock advances across wrap")
CheckNear(clock.Estimate(1150), Double(Long($ffffffff:UInt) + 2) + 3.0, 0.0001, "wrapped clock estimate")
Check(Not clock.Observe(1, 1200), "clock ignores duplicate tick")

Local delay:TSnapshotDelay = TSnapshotDelay.Create(60.0, 2.0, 12.0, 1.0, 1.0)
Check(delay <> Null, "create adaptive delay")
delay.Observe(1, 0)
delay.Observe(2, 16)
CheckNear(delay.DelayTicks(), 2.0, 0.0001, "stable arrivals retain base delay")
delay.Observe(3, 116)
CheckNear(delay.DelayTicks(), 8.0, 0.0001, "delay rises for late arrival")
delay.Observe(4, 1116)
CheckNear(delay.DelayTicks(), 12.0, 0.0001, "delay is capped")
delay.Observe(64, 2116)
CheckNear(delay.DelayTicks(), 11.0, 0.0001, "delay recovers gradually")
delay.Clear()
CheckNear(delay.DelayTicks(), 2.0, 0.0001, "delay resets to base")

Print "GameNet.Snapshot tests passed"
