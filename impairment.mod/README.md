# GameNet.Impairment

`GameNet.Impairment` is a bounded transport decorator for repeatable adverse-network testing. It can add outbound latency and jitter, constrain bandwidth, and inject packet loss, duplication, and reordering around any `INetTransport` implementation.

```blitzmax
Local policy:SImpairmentConfig = New SImpairmentConfig( ..
	80, ..   ' base one-way latency in milliseconds
	20, ..   ' symmetric jitter
	500, ..  ' 5% loss (values are out of 10,000)
	100, ..  ' 1% duplication
	200, ..  ' 2% explicit reordering
	100, ..  ' maximum extra reorder delay
	32000, .. ' bytes per second; zero is unlimited
	IMPAIRMENT_DELIVERY_UNRELIABLE | IMPAIRMENT_DELIVERY_UNRELIABLE_SEQUENCED)

Local network:INetTransport = TImpairedTransport.Create(realTransport, 128, 1200, policy, 12345)
```

The random seed makes a run repeatable when calls occur in the same order. The decorator preallocates its packet queue and storage; a full queue returns `ETransportResult.WouldBlock` rather than allocating or silently losing the original packet.

## Direction and delivery semantics

Impairment is outbound. Wrap every endpoint whose outgoing packets should be affected. This makes one configured latency value a one-way delay rather than applying it twice at one endpoint.

The delivery mask selects which delivery modes are impaired. Non-selected packets pass directly to the backend. The default is `IMPAIRMENT_DELIVERY_ALL`; selecting only the two unreliable constants is useful when reliable control messages should remain intact.

Loss and duplication occur above the wrapped backend. They can therefore affect `ReliableOrdered` packets when that mode is selected. That is intentional: the decorator can test application behaviour during blackouts and pathological delivery failures, rather than testing ENet's internal retransmission algorithm.

Connection, disconnection, and backend error events are passed through immediately. Calling `Disconnect` removes delayed packets for that peer before forwarding the operation.

## Deterministic clock

Normal decorators read `MilliSecs()` automatically. Tests can pass `True` as the final `Create` argument and advance time explicitly:

```blitzmax
Local impaired:TImpairedTransport = TImpairedTransport.Create(realTransport, 32, 1200, policy, 7, True)
impaired.SetTime(1000)
```

Call `SetTime` before sending or polling at each simulated instant. Time comparisons tolerate 32-bit millisecond wraparound as long as scheduled delays remain below half the counter range.

The decorator can sit directly beneath `GameNet.Session`. In manual-clock tests, set the decorator time before calling the session's `PollAt` for the same instant.

`Stats()` reports the current queue depth and cumulative sent, dropped, duplicated, reordered, overflow, and deferred-send-failure counts. A backend failure which occurs after a delayed `Send` is returned through `Poll` as an error event. Its code is `IMPAIRMENT_ERROR_SEND_BASE + Int(result)`.
