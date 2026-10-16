# GameNet.LANDiscovery

`GameNet.LANDiscovery` supplies a small, service-free browser for games on the
same IPv4 network. It complements `GameNet.ENet`; it does not carry gameplay
traffic and is not an Internet matchmaking or NAT-traversal service.

The host answers versioned UDP discovery queries with a bounded description of
its game. A browser filters replies by application identifier and protocol
version, takes the host address from the datagram source, updates duplicate
results, and removes games which stop responding.

```blitzmax
Local details:SLANAdvertisement = New SLANAdvertisement( ..
	"net.example.my-game", 1, "Bruce's game", 27015, 1, 4 )

Local advertiser:TLANDiscoveryHost = TLANDiscoveryHost.Create(details)

Local browser:TLANDiscoveryBrowser = TLANDiscoveryBrowser.Create( ..
	"net.example.my-game", 1 )

' Call both from the ordinary update loop.
advertiser.Update()
browser.Update()

For Local index:Int = 0 Until browser.Count()
	Local game:TLANDiscoveredGame = browser.Game(index)
	Print game.Name() + " at " + game.Address() + ":" + game.Port()
Next
```

When a player chooses a result, pass its address and port to
`TENetTransport.Connect`. The subsequent `GameNet.Session` handshake remains
responsible for accepting or rejecting the connection. Discovery packets are
unauthenticated and their names and metadata must be treated as untrusted
display data.

The default browser broadcasts once per second and expires a result after 3.5
seconds. Both intervals and the discovery port are configurable. Browsers keep
at most 32 results by default, and hosts and browsers process at most 64
datagrams in one update so unexpected LAN traffic cannot grow memory or consume
an entire frame. Those bounds are configurable at creation. `Refresh` can send
to a directed broadcast address when a network does not forward the limited
broadcast address, and can send to `127.0.0.1` for local tests.

On iOS, the generated application must include a meaningful
`NSLocalNetworkUsageDescription`. On Android, it must request the `INTERNET`
permission. This module uses UDP broadcast rather than multicast, so it does
not require Apple's multicast entitlement or Android's multicast lock.
