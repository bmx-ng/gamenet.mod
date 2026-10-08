# GameNet.ENet

`GameNet.ENet` implements `INetTransport` using the native ENet UDP library
bundled with BlitzMax NG. It supports listening hosts and asynchronous outgoing
connections using hostnames, IPv4, or IPv6 addresses.

The backend allocates peer tables and one reusable native event at creation.
Received packets are exposed directly from ENet and are destroyed on the next
`Poll` call, avoiding an intermediate managed byte array.

Each logical channel uses three ENet channels:

| GameNet mode | ENet behaviour |
| --- | --- |
| `Unreliable` | Unsequenced unreliable packet |
| `UnreliableSequenced` | Sequenced unreliable packet |
| `ReliableOrdered` | Reliable ordered packet |

Consequently, one connection supports up to 85 logical GameNet channels.

```blitzmax
Local server:TENetTransport = TENetTransport.Listen(27015)

Local client:TENetTransport = TENetTransport.CreateClient()
Local pendingPeer:SNetPeer
client.Connect("127.0.0.1", 27015, pendingPeer)
```

Connections complete asynchronously. The pending handle passed to `Connect` is
also returned by the resulting `Connected` or `Disconnected` event. Poll each
transport every game update. Packet views in `Data` events are borrowed until
the next `Poll` call on the receiving transport.
