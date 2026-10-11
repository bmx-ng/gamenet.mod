# Steam lobby/session example

This desktop example exercises the complete initial Steam path:

`GameNet.Online -> GameNet.SteamOnline -> Steam lobby -> GameNet.Steam -> GameNet.Session`

Steam must be running. During local development, place an appropriate
`steam_appid.txt` beside the executable and copy the platform Steam API runtime
library there as required by `Steam.SteamSDK`. Use two computers signed into
different Steam accounts.

1. Start the example on both computers.
2. Select **Create Lobby** on one computer.
3. Select **Invite Friends** and accept through Steam, or select **Find Lobby**
   on the other computer to join the first matching test lobby.
4. Select **Start Match** on both. The lobby owner coordinates the start.
5. Select **Send Packet** to verify bidirectional reliable traffic.
