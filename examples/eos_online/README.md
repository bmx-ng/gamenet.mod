# EOSOnline integration test

This Max2D application validates the complete `GameNet.EOSOnline` path with two
accounts in Epic's Developer Authentication Tool:

1. Auth and Connect login for both accounts;
2. public lobby creation and attribute publication;
3. bucket and property discovery from the second account;
4. lobby join and two-member roster propagation;
5. lobby-owner match start;
6. `GameNet.EOSP2P` transport handoff; and
7. reliable ordered `PING`/`PONG` exchange.

Build it as a GUI application:

```sh
bmk makeapp -r -t gui -o examples/eos_online/eos_online_test examples/eos_online/eos_online_test.bmx
```

On macOS, copy the EOS runtime into the generated bundle before launching:

```sh
cp ../eos.mod/sdk.mod/SDK/Bin/libEOSSDK-Mac-Shipping.dylib examples/eos_online/eos_online_test.app/Contents/MacOS/
```

Keep the Developer Authentication Tool open. The ignored
`../eos.mod/sdk.mod/examples/eos.local.conf` must contain
`DEV_AUTH_CREDENTIAL` and `DEV_AUTH_CREDENTIAL_2` for two different accounts.
You may instead pass the config path and second credential name as application
arguments.

The application writes a timestamped live trace to
`/tmp/gamenet-eos-online.log`. To watch authentication, lobby notifications,
match handoff, EOS P2P connection state, and the PING/PONG exchange as they
happen, run:

```sh
tail -f /tmp/gamenet-eos-online.log
```
