SuperStrict

Framework BRL.StandardIO
Import GameNet.LANDiscovery

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local advertisement:SLANAdvertisement = New SLANAdvertisement("net.bmx-ng.gamenet.test", 7, "Loopback game", 46329, 1, 4, 3, "map=small")
Check(advertisement.IsValid(), "valid advertisement")

Local invalid:SLANAdvertisement = advertisement
invalid.players = 5
Check(Not invalid.IsValid(), "reject player count above capacity")

Local host:TLANDiscoveryHost = TLANDiscoveryHost.Create(advertisement, 0)
Check(host <> Null, "create host on free discovery port")
Check(host.DiscoveryPort() > 0, "resolve allocated discovery port")

Local browser:TLANDiscoveryBrowser = TLANDiscoveryBrowser.Create(advertisement.gameId, advertisement.protocolVersion, host.DiscoveryPort(), 0, 100)
Check(browser <> Null, "create browser")
Check(TLANDiscoveryBrowser.Create(advertisement.gameId, advertisement.protocolVersion, host.DiscoveryPort(), 0, 100, 0) = Null, "reject empty result capacity")
Check(browser.Refresh("127.0.0.1"), "send directed query")

Local deadline:Int = MilliSecs() + 1000
Local answered:Int
Local accepted:Int
While browser.Count() = 0 And MilliSecs() < deadline
	answered :+ host.Update()
	accepted :+ browser.UpdateAt(10)
	Delay 1
Wend

Check(answered > 0, "host answered directed query on port " + host.DiscoveryPort())
Check(accepted > 0, "browser accepted response")
Check(browser.Count() = 1, "discover host")
Local game:TLANDiscoveredGame = browser.Game(0)
Check(game <> Null, "get discovered game")
Check(game.Address() = "127.0.0.1", "use datagram source address")
Check(game.Port() = advertisement.gamePort, "game port")
Check(game.Name() = advertisement.name, "game name")
Check(game.Players() = 1 And game.Capacity() = 4, "player counts")
Check(game.Flags() = 3 And game.Metadata() = "map=small", "flags and metadata")

advertisement.players = 2
advertisement.name = "Updated game"
Check(host.SetAdvertisement(advertisement), "update advertisement")
Check(browser.Refresh("127.0.0.1"), "send second query")
deadline = MilliSecs() + 1000
While game.Players() <> 2 And MilliSecs() < deadline
	host.Update()
	browser.UpdateAt(20)
	Delay 1
Wend
Check(browser.Count() = 1 And game.Players() = 2 And game.Name() = "Updated game", "refresh existing result")

Local incompatible:TLANDiscoveryBrowser = TLANDiscoveryBrowser.Create(advertisement.gameId, advertisement.protocolVersion + 1, host.DiscoveryPort(), 0, 100)
Check(incompatible <> Null And incompatible.Refresh("127.0.0.1"), "send incompatible query")
deadline = MilliSecs() + 50
While MilliSecs() < deadline
	host.Update()
	incompatible.UpdateAt(20)
	Delay 1
Wend
Check(incompatible.Count() = 0, "ignore incompatible protocol")

browser.UpdateAt(121)
Check(browser.Count() = 0, "expire stale result")

incompatible.Close()
browser.Close()
host.Close()

Print "LAN discovery tests passed"
