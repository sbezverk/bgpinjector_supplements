# BGP-LS API fixtures

These request bodies demonstrate the current BGP-LS API shape for all
implemented NLRI kinds, excluding BGP-LS-SPF:

- Node
- Link
- IPv4 topology prefix
- IPv6 topology prefix
- SRv6 SID
- SR Policy candidate path

The Node examples cover IS-IS Levels 1 and 2, OSPFv2, OSPFv3, SR local blocks,
and SRv6 capabilities for IS-IS and OSPFv3. The Link examples cover IS-IS Level 1 and
Level 2, IPv4 and IPv6 link descriptors, OSPFv2, OSPFv3, and SRv6 End.X for
IS-IS and OSPFv3. Three additional files show BGP-LS-VPN forms for Node, Link,
and IPv4 prefix NLRIs. Those kinds use the same `link_state` and `attributes`
objects with `address_family: "bgp-ls-vpn"` and an RD in the NLRI.

All fixtures use `fd00:100::2` as their IPv6 BGP next hop, matching the
injector endpoint in the current testbed. Before using a fixture in another
testbed, update its `next_hops` value to the injector's reachable local BGP
endpoint, using the same address family as the BGP session (IPv4 for an IPv4
session or IPv6 for an IPv6 session). This next hop is independent of the
topology being advertised: IPv4 link descriptors remain IPv4 even when the BGP
next hop is IPv6. These files are individual `POST /v1/routes` request bodies.

For an iBGP session, include the top-level `local_pref` field in each
announcement. BGP requires LOCAL_PREF on UPDATEs sent to internal peers; omit
it when advertising to an eBGP peer (except for BGP confederation use). The
field is peer-specific, so choose it based on the session that will carry the
route. For example, the current testbed uses `"local_pref": 100` for its
iBGP session; `100` is a lab choice, not a value prescribed by BGP.

For example:

```sh
curl --fail-with-body -sS -X POST http://127.0.0.1:8080/v1/routes \
  -H 'content-type: application/json' \
  --data-binary @testdata/injection_cases/bgp_ls/node_isis.json
```

Node, Link, Prefix, SRv6 SID, and SR Policy Candidate Path BGP-LS UPDATE
encoding is implemented. Fixture-driven unit tests parse, validate, and build
UPDATEs for these examples; separate SR Policy regression tests also verify
the encoded NLRI and attribute bytes and reject invalid user input. The Prefix
fixtures exercise IPv4 and IPv6 NLRIs across IS-IS, OSPFv2, and OSPFv3,
including Prefix-SID, Prefix Range, flexible algorithm, opaque, and SRv6
locator attributes. The BGP-LS-VPN examples are documented but are not in that
test yet. BGP-LS-SPF-specific attributes are not included in these regular
BGP-LS fixtures. The Link fixtures omit `igp_metric` to keep the examples
focused on the requested protocol/address-family combinations; dedicated
wire-format tests cover protocol-specific IGP metric lengths and boundary
values.

| File | NLRI | Example coverage |
|---|---|---|
| `node_isis.json` | Node | IS-IS node name, flags, SR algorithms and SRGB |
| `node_isis_level1.json` | Node | IS-IS Level 1 protocol ID |
| `node_isis_srv6.json` | Node | IS-IS SRv6 capability and node identifier |
| `node_isis_sr_local_block.json` | Node | IS-IS SR local block label and range encoding |
| `node_ospf.json` | Node | OSPF router/area descriptors, router ID and MSD |
| `node_ospfv3.json` | Node | OSPFv3 router/area descriptors and IPv6 router ID |
| `node_ospfv3_srv6.json` | Node | OSPFv3 SRv6 capability and node identifier |
| `link_isis.json` | Link | IS-IS Level 2 over IPv4, TE metric, bandwidth, valid local-label and index Adj-SIDs, and SRLG |
| `link_isis_ipv6.json` | Link | IS-IS Level 2 over IPv6 |
| `link_isis_ipv6_srv6.json` | Link | IS-IS Level 2 over IPv6 with SRv6 End.X SID |
| `link_isis_level1_ipv4.json` | Link | IS-IS Level 1 over IPv4 |
| `link_ospfv2.json` | Link | OSPFv2 over IPv4 |
| `link_ospfv3.json` | Link | OSPFv3 over IPv6 |
| `link_ospfv3_ipv6_srv6.json` | Link | OSPFv3 over IPv6 with SRv6 End.X SID |
| `prefix_ipv4_isis.json` | IPv4 prefix | Metric, route tag and label Prefix-SID |
| `prefix_ipv4_ospf.json` | IPv4 prefix | OSPF route type, forwarding address and opaque attribute |
| `prefix_ipv6_ospfv3.json` | IPv6 prefix | IPv6 router ID, prefix metric and SRv6 locator |
| `prefix_ipv6_isis.json` | IPv6 prefix | Multi-topology, source router ID, label Prefix-SID in a prefix range |
| `prefix_ipv6_isis_range_index.json` | IPv6 prefix | IS-IS multi-topology Prefix Range with index-encoded Prefix-SID |
| `srv6_sid_direct.json` | SRv6 SID | Direct protocol SID descriptor, endpoint behavior and SID structure |
| `srv6_sid_bgp.json` | SRv6 SID | BGP SID descriptor, endpoint behavior and PeerNode SID context |
| `srv6_sid_isis_mtid.json` | SRv6 SID | IS-IS SID descriptor with non-default Multi-Topology ID 7 |
| `sr_policy_mpls.json` | SR Policy candidate path | MPLS binding SID, candidate state, constraints and segment list |
| `sr_policy_srv6.json` | SR Policy candidate path | IPv6 endpoint, SRv6 binding SID and SRv6 segment list |
| `vpn_node.json` | VPN Node | Node NLRI with RD |
| `vpn_link.json` | VPN Link | Link NLRI with RD and numbered link descriptors |
| `vpn_prefix_ipv4.json` | VPN IPv4 prefix | Prefix NLRI with RD and prefix metric |

SRv6 SID attributes require explicit `endpoint_behavior`, `flags`, and
`algorithm` values. Use zero explicitly when that is the intended value.

