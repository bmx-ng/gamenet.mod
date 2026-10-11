SuperStrict

Framework BRL.StandardIO
Import GameNet.GameKitOnline

?macos Or ios
Local service:TGameKitOnlineService = TGameKitOnlineService.Create()
If Not service Then Throw "could not create GameKit online service"
If service.ProviderName() <> "GameKit" Then Throw "unexpected provider name"
If Not OnlineHasCapabilities(service.Capabilities(), EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport) Then Throw "missing GameKit capabilities"
If OnlineHasCapabilities(service.Capabilities(), EOnlineCapability.FindLobbies) Then Throw "unexpected lobby search capability"
Print "GameNet.GameKitOnline contract tests passed"
?Not macos And Not ios
Print "GameNet.GameKitOnline is unavailable on this target"
?
