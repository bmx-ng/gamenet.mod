# GameNet.Loopback

`GameNet.Loopback` connects two `INetTransport` endpoints inside one process.
It is intended for protocol tests, local multiplayer, examples, and simulation
without a network connection.

The pair allocates a fixed event queue and packet arena when it is created.
Sending copies bytes into that arena; sending and polling do not create managed
objects while capacity remains available.

```blitzmax
Local pair:TLoopbackPair = TLoopbackPair.Create()
Local client:TLoopbackTransport = pair.First()
Local server:TLoopbackTransport = pair.Second()
```

Each endpoint initially reports one `Connected` event. As with every GameNet
transport, a received packet view is borrowed until the next call to `Poll` on
that endpoint.
