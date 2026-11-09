# SRv6 Prefix-SID VPNv4 and VPNv6 test routes

`inject_routes.sh` announces a test VPNv4 route with PE2's `uDT4` service SID
and a test VPNv6 route with PE2's `uDT6` service SID. The observed values are
`fcbb:bb00:12:e002::` (`uDT4`) and `fcbb:bb00:12:e003::` (`uDT6`). Both routes
use PE2's BGP next hop `fc00::12`, the `1:1` route target configured for
`CUST`, and distinct test prefixes/RDs.

The next hop and service SIDs have different roles. `fc00::12` identifies the
BGP next hop. The two service SIDs are programmed on PE2 for VRF `CUST`; the
script defaults to the values in the supplied SID table. If PE2 uses one
`uDT46` SID for both address families, adapt the script to use that SID with
endpoint behavior 64 in both requests.

Before announcing, set the SIDs and confirm the SID Structure fields match
PE2's locator/SID allocation. For the shown `/48` uSID locator and 32-bit
block/16-bit uSID format, the script uses locator block/node/function/argument
lengths `32/16/16/0`, with transposition length and offset both zero. It uses
the IANA uDT4 and uDT6 endpoint behavior values 63 and 62. For zero
transposition RFC 9252 uses the Implicit NULL VPN label (value 3). The fixture
does not signal or select an SR Policy; it tests the advertised VPN service
SID and route handling.

```bash
./injection_cases/srv6_prefix_sid_pe2/inject_routes.sh announce
```

Override `PE2_DT4_SID` or `PE2_DT6_SID` if the service SIDs change.

To withdraw the routes, use the same address family, RD, prefix, and label:

```bash
./injection_cases/srv6_prefix_sid_pe2/inject_routes.sh withdraw
```

For VPNv4 over the IPv6 next hop, first check `/v1/session` reports VPNv4 in
`negotiated_families` and `vpnv4->ipv6` in
`negotiated_extended_next_hop_mappings`. The route target is `1:1`; the sample
prefixes are documentation ranges and are for route inspection, not a working
CE ping destination.

The requests omit `path_id` because the current injector session does not
negotiate ADD-PATH. If ADD-PATH is enabled later, the session requires a path
ID for these routes; update the fixture to match the negotiated session.

After injection, inspect the injector response/log and PE1's VPNv4/VPNv6 BGP
routes. Share the detailed route output, including the received Prefix-SID,
next hop, label, and whether the route was accepted/installed.
