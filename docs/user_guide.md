# bgpinjector User Guide

This guide explains how to run `bgpinjector`, establish one BGP session, and
inject or withdraw routes through its HTTP API. It is intended for support and
test engineers using either a standalone binary or a Docker container.

## 1. What bgpinjector does

`bgpinjector` is an active BGP speaker with a small HTTP API. It:

- opens one outbound TCP/BGP session to a configured router;
- negotiates the address families offered by both peers;
- accepts route advertisements and withdrawals over HTTP;
- converts normalized JSON requests into BGP UPDATE messages;
- queues and rate-limits UPDATE transmission; and
- automatically reconnects if the BGP session goes down.

It is a route-generation and troubleshooting tool, not a routing daemon or a
persistent RIB. Injected routes are not stored for replay. If the BGP session
resets, submit the desired advertisements again after the session is ready.

> **Safety:** bgpinjector sends real BGP UPDATE messages. Use a lab session or
> restrictive import policy, confirm every prefix and route target, and keep
> matching withdrawal requests ready before beginning a test.

## 2. Requirements and testbed preparation

You need:

- a compatible `bgpinjector` binary or container image;
- IP reachability from the injector host or container to TCP port 179 on the
  router;
- `curl` for the examples in this guide;
- `jq` if formatted JSON output is desired; and
- a BGP neighbor on the router configured for the injector's actual TCP source
  address and local AS.

On the router, confirm that:

- the configured neighbor address is the source address the operating system
  or container will use for the outbound TCP connection;
- the neighbor's remote AS matches `--local-as`;
- every address family you plan to inject is activated for the neighbor;
- import policy allows the test routes and, for VPN routes, the route target;
- the advertised next hops are resolvable if routes must enter the RIB/FIB;
- ADD-PATH receive is enabled for each family where multiple paths will be
  injected; and
- no TCP MD5 password is required. The current CLI has no BGP password option.

### BGP source-address behavior

Use `--local-address` to bind the outbound BGP TCP connection to a specific
IPv4 or IPv6 address. The address must exist in bgpinjector's network namespace;
the TCP source port remains ephemeral. `--router-id` only sets the BGP
Identifier in the OPEN message and is independent of the TCP source address.

If `--local-address` is omitted, the host operating system selects the source
according to its route toward `--speaker-address`. In a container, Docker
networking or NAT can still change the source seen by the router.

Examples:

```bash
--local-address=25.25.25.5
--local-address=fd04:b400::706
--local-address=fe80::706%eth0
```

IPv6 link-local addresses require an interface zone. The configured address is
reported as `local_address` by `/v1/session`; while the TCP connection exists,
`local_endpoint` also reports the selected address and ephemeral port.

Before configuring the neighbor, verify the selected source address from the
same environment in which bgpinjector will run. On Linux, a useful check is:

```bash
ip route get 192.0.2.1
```

Replace `192.0.2.1` with the router's BGP address. The output normally includes
the selected `src` address.

## 3. Running the standalone binary

Use a binary built for the host operating system and CPU architecture. For
example, after receiving a Linux AMD64 binary:

```bash
install -m 0755 bgpinjector-linux-amd64 ./bgpinjector
./bgpinjector --help
```

Start a basic iBGP session that preserves next hops supplied in API requests:

```bash
./bgpinjector \
  --speaker-address=192.0.2.1:179 \
  --local-address=25.25.25.5 \
  --local-as=65137 \
  --router-id=25.25.25.5 \
  --api-address=127.0.0.1:8080 \
  --next-hop-mode=preserve \
  --rate=100 \
  --v=5
```

Replace all example addresses and AS numbers with testbed values. Keep the API
bound to `127.0.0.1` unless remote API access is explicitly required.

Stop a foreground process with `Ctrl-C`. `SIGTERM` also triggers an orderly
shutdown.

### Important command-line options

| Option | Default | Purpose |
|---|---|---|
| `--speaker-address` | `127.0.0.1:179` | Router address and TCP port for the outbound BGP session. |
| `--local-address` | unset | Local IPv4 or IPv6 address used to source the outbound BGP TCP session. |
| `--api-address` | `127.0.0.1:8080` | HTTP API listen address. |
| `--local-as` | `65000` | ASN sent in the local BGP OPEN. |
| `--router-id` | `127.0.0.1` | BGP Identifier; this is not the TCP source address. |
| `--hold-time` | `90` | Proposed BGP hold time in seconds. |
| `--retry-interval` | `5s` | Delay between connection attempts. |
| `--next-hop-mode` | `preserve` | Preserve request next hops or rewrite them. |
| `--rewrite-next-hop` | unset | IPv4 next hop used in rewrite mode. |
| `--rewrite-next-hop-v6` | unset | IPv6 next hop used in rewrite mode. |
| `--rate` | `10` in API-only mode | Target UPDATE processing rate per second. |
| `--queue-size` | `100000` | Maximum queued route events; allowed maximum is 5,000,000. |
| `--add-path-send-families` | unset | Comma-separated families for which bgpinjector advertises ADD-PATH send capability. |
| `--ingress-type` | `none` | `none` for API use or `rislive` for the live RIS feed. |
| `--v` | `0` | Logging verbosity; `5` is useful for normal troubleshooting. |

Go flags accept either one or two leading hyphens.

## 4. Running as a Docker container

Replace `<tag>` with the image tag supplied for your test. The repository's
default image name is `docker.io/sbezverk/bgpinjector`.

```bash
docker pull docker.io/sbezverk/bgpinjector:<tag>
```

If an image archive was supplied instead of a registry tag:

```bash
docker load -i bgpinjector-image.tar
docker images | grep bgpinjector
```

### Linux host networking

Host networking is usually the simplest option when the router already peers
with an address on the Linux host:

```bash
docker run -d \
  --name bgpinjector \
  --restart unless-stopped \
  --network host \
  docker.io/sbezverk/bgpinjector:<tag> \
  --speaker-address=192.0.2.1:179 \
  --local-address=25.25.25.5 \
  --local-as=65137 \
  --router-id=25.25.25.5 \
  --api-address=127.0.0.1:8080 \
  --next-hop-mode=preserve \
  --rate=100 \
  --v=5
```

Host networking behavior differs on Docker Desktop. Verify it before relying
on this example outside native Linux.

### Docker bridge networking

With bridge networking, listen on all container interfaces and publish the API
only on host loopback:

```bash
docker run -d \
  --name bgpinjector \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  docker.io/sbezverk/bgpinjector:<tag> \
  --speaker-address=192.0.2.1:179 \
  --local-address=192.0.2.2 \
  --local-as=65137 \
  --router-id=25.25.25.5 \
  --api-address=0.0.0.0:8080 \
  --next-hop-mode=preserve \
  --rate=100 \
  --v=5
```

The value passed to `--local-address` must be assigned inside the container.
Docker/NAT may still translate it before the connection reaches the router.
Check the SYN packet or router logs and configure networking and the BGP
neighbor accordingly. A dedicated Docker network such as macvlan may be needed
when the container must have a specific address visible to the router.

Container operations:

```bash
docker logs -f bgpinjector
docker restart bgpinjector
docker stop bgpinjector
docker rm bgpinjector
```

## 5. Verifying the BGP session

The process health endpoint confirms that the HTTP service is alive:

```bash
curl --fail --silent --show-error http://127.0.0.1:8080/healthz
```

Readiness is stricter. It returns HTTP `200` only when the BGP session is
established, and `503` while the session is down:

```bash
curl --include --silent http://127.0.0.1:8080/readyz
```

Inspect the full session state:

```bash
curl --silent --show-error http://127.0.0.1:8080/v1/session | jq
```

Before injecting, verify at least:

- `state` is `established`;
- `remote_as` and `remote_id` identify the expected router;
- `next_hop_mode` is correct;
- the required family appears in `negotiated_families`; and
- any required family appears in `negotiated_add_path_send_families`.

Example readiness fields:

```json
{
  "state": "established",
  "speaker_address": "192.0.2.1:179",
  "local_as": 65137,
  "router_id": "25.25.25.5",
  "remote_as": 65137,
  "next_hop_mode": "preserve",
  "negotiated_families": [
    "ipv4/unicast",
    "ipv6/unicast",
    "vpnv4",
    "vpnv6"
  ]
}
```

List available statistics and retrieve all statistics:

```bash
curl --silent http://127.0.0.1:8080/v1/stats | jq
curl --silent http://127.0.0.1:8080/v1/stats/all | jq
```

## 6. Next-hop modes

### Preserve mode

Use preserve mode when the request must carry a specific simulated remote
next hop:

```text
--next-hop-mode=preserve
```

Every announcement must provide an appropriate `next_hops` value. This is the
recommended mode for VPN and recursive-resolution testing.

### Rewrite mode

Use rewrite mode when all announcements should use a known reachable next hop:

```text
--next-hop-mode=rewrite \
--rewrite-next-hop=192.0.2.25 \
--rewrite-next-hop-v6=2001:db8::25
```

At least one rewrite address is required in rewrite mode. The policy applies
to normalized `/v1/routes` announcements, not raw UPDATEs.

Rewrite mode preserves the next-hop address family requested by a normalized
route. In particular:

- VPNv4 with an IPv4 next hop uses `--rewrite-next-hop`;
- VPNv4 with an IPv6 next hop uses `--rewrite-next-hop-v6`;
- VPNv4 with a global and link-local IPv6 pair is rewritten to the configured
  single IPv6 rewrite address; and
- VPNv4 is rejected when the matching rewrite address is not configured.

Rewrite mode never changes a VPNv4 route from an IPv4 next hop to IPv6, or
from IPv6 to IPv4, merely because another rewrite address or capability is
available.

## 7. Route API basics

Send normalized routes to:

```text
POST http://127.0.0.1:8080/v1/routes
Content-Type: application/json
```

The endpoint accepts one JSON object or an array of objects. Request bodies are
limited to 1 MiB. A successful request returns HTTP `202 Accepted`, for example:

```json
{
  "accepted": 1,
  "updates": [
    {
      "prefix": "203.0.113.0/24",
      "action": "announce",
      "queued": true
    }
  ]
}
```

`queued: true` means the request passed validation and entered the local queue.
It does not prove that the router accepted or installed the route. Check
`sent_updates`, the router's received-route view, BGP table, RIB, and FIB as
appropriate.

The most commonly used normalized families are:

| `address_family` | NLRI fields | Announcement next hop |
|---|---|---|
| `ipv4/unicast` | `prefix` | One IPv4 address. |
| `ipv6/unicast` | `prefix` | One global IPv6 address, optionally followed by a link-local IPv6 address where supported. |
| `ipv4/labeled-unicast` | `labels`, `prefix` | One IPv4 address. |
| `vpnv4` | `labels`, `rd`, `prefix` | One IPv4 address, one global IPv6 address, or a global and link-local IPv6 pair. IPv6 requires negotiated Extended Next Hop Encoding. |
| `vpnv6` | `labels`, `rd`, `prefix` | One IPv6 address; the tested IPv4-mapped form is also supported. |

Only inject a family shown in `negotiated_families`.

### Announcement-only fields

Common announcement fields include:

- `next_hops`: array of next-hop addresses;
- `origin`: `igp`, `egp`, or `incomplete`;
- `as_path`: simple AS sequence such as `[64512, 64513]`;
- `as_path_segments`: structured sequence/set form for advanced cases;
- `med` and `local_pref`;
- `communities`: standard communities such as `"64512:100"` or
  `"no-export"`;
- `large_communities`; and
- `extended_communities`.

Use either `as_path` or `as_path_segments`, not both. For eBGP announcements,
bgpinjector prepends its local AS unless it is already first. For iBGP, it
leaves the supplied AS path unchanged.

Withdrawals normally contain only `address_family`, `action`, `nlri`, and, when
ADD-PATH is negotiated, `path_id`. Do not copy next hop or path attributes into
a withdrawal.

### BGP-LS Node, Link, and Prefix routes

The normalized route API supports BGP-LS Node, Link, and IPv4/IPv6 Prefix
advertisements. Set `address_family` to `bgp-ls`. The BGP-LS protocol ID,
instance ID, NLRI data, and NLRI attributes go inside `nlri`; common BGP path
attributes such as `next_hops`, `origin`, and `local_pref` stay at the request
level. The peer must negotiate BGP-LS before these routes can be sent.

These examples use the IPv6 next hop from the BGP-LS testbed fixtures. Replace
it with a next hop appropriate for the peer and testbed. The complete examples
are in [`testdata/injection_cases/bgp_ls`](../testdata/injection_cases/bgp_ls/README.md).

**Node** (from [`node_isis.json`](../testdata/injection_cases/bgp_ls/node_isis.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "isis-level-2",
    "instance_id": "0",
    "link_state": {
      "kind": "node",
      "local_node": {
        "autonomous_system": 65000,
        "igp_router_id": {
          "kind": "isis-system-id",
          "value": "0000.0000.0001"
        }
      }
    },
    "attributes": {
      "node_name": "pe1.example.net",
      "sr_algorithms": [0, 1]
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

**Link** (from [`link_isis.json`](../testdata/injection_cases/bgp_ls/link_isis.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "isis-level-2",
    "instance_id": "0",
    "link_state": {
      "kind": "link",
      "local_node": {
        "autonomous_system": 65000,
        "igp_router_id": {"kind": "isis-system-id", "value": "0000.0000.0001"}
      },
      "remote_node": {
        "autonomous_system": 65000,
        "igp_router_id": {"kind": "isis-system-id", "value": "0000.0000.0002"}
      },
      "link_descriptors": {
        "ipv4_interface_address": "192.0.2.1",
        "ipv4_neighbor_address": "192.0.2.2"
      }
    },
    "attributes": {
      "te_default_metric": 20,
      "administrative_group": 5
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

**IPv4 Prefix** (from [`prefix_ipv4_isis.json`](../testdata/injection_cases/bgp_ls/prefix_ipv4_isis.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "isis-level-2",
    "instance_id": "0",
    "link_state": {
      "kind": "ipv4_topology_prefix",
      "local_node": {
        "autonomous_system": 65000,
        "igp_router_id": {"kind": "isis-system-id", "value": "0000.0000.0001"}
      },
      "prefix": "198.51.100.0/24",
      "prefix_descriptors": {"multi_topology_id": 0}
    },
    "attributes": {
      "prefix_metric": 20,
      "igp_route_tags": [100, 200]
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

For IPv6 Prefix NLRIs, use `kind: "ipv6_topology_prefix"` and an IPv6 CIDR.
The fixtures also show OSPFv2 and OSPFv3 Node/Link/Prefix examples, IS-IS
levels 1 and 2, and SRv6 Node and Link attributes. Prefix fixtures cover
IPv4/IPv6, IS-IS/OSPF, Prefix-SID, Prefix Range, flexible algorithm metrics,
and SRv6 locator attributes. See the fixture directory for those variants.

The address family is still `bgp-ls` for both IPv4 and IPv6 Prefix NLRIs; the
prefix kind selects the BGP-LS NLRI type. Keep the prefix canonical (host bits
clear), and make sure its address family matches its kind. A queued HTTP
response confirms API acceptance; verify the received route and decoded
attributes on the peer as described in [Verification on the router](#15-verification-on-the-router).

#### SRv6 SID NLRI

Use `link_state.kind: "srv6_sid"` for an SRv6 SID NLRI. The SID is an IPv6
address in `link_state.descriptors.sid`; the encoder places it in the SRv6 SID
Information TLV (type 518). The top-level BGP-LS `protocol_id` identifies the
source protocol, and `instance_id` supplies the NLRI identifier. Do not put
either field inside `link_state`.

The `attributes` object must include `endpoint_behavior`, `flags`, and
`algorithm`. Supply zero explicitly when that is the intended value. The
endpoint behavior is encoded in the mandatory SRv6 Endpoint Behavior TLV
(type 1250). `sid_structure` is optional and uses TLV 1252. For BGP EPE SIDs,
include the `peer_node_sids` data; each entry is encoded as an SRv6 BGP
PeerNode SID TLV (type 1251). [RFC 9514](https://www.rfc-editor.org/rfc/rfc9514.html)
defines these TLVs and the SRv6 SID NLRI format.

**Direct protocol SID** (from
[`srv6_sid_direct.json`](../testdata/injection_cases/bgp_ls/srv6_sid_direct.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "direct",
    "instance_id": "0",
    "link_state": {
      "kind": "srv6_sid",
      "local_node": {
        "autonomous_system": 65000,
        "igp_router_id": {"kind": "ipv4-address", "value": "192.0.2.1"}
      },
      "descriptors": {"sid": "2001:db8:100::1"}
    },
    "attributes": {
      "endpoint_behavior": 1,
      "flags": 0,
      "algorithm": 0,
      "sid_structure": {
        "locator_block_length": 32,
        "locator_node_length": 16,
        "function_length": 16,
        "argument_length": 0
      }
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

**BGP EPE PeerNode SID** (from
[`srv6_sid_bgp.json`](../testdata/injection_cases/bgp_ls/srv6_sid_bgp.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "bgp",
    "instance_id": "1",
    "link_state": {
      "kind": "srv6_sid",
      "local_node": {
        "autonomous_system": 65000,
        "bgp_router_id": "192.0.2.1"
      },
      "descriptors": {"sid": "2001:db8:200::1"}
    },
    "attributes": {
      "endpoint_behavior": 5,
      "flags": 0,
      "algorithm": 0,
      "peer_node_sids": [
        {"peer_as_number": 65001, "peer_bgp_identifier": "192.0.2.2"}
      ],
      "sid_structure": {
        "locator_block_length": 32,
        "locator_node_length": 16,
        "function_length": 16,
        "argument_length": 0
      }
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

**IS-IS SID with non-default MT-ID 7** (from
[`srv6_sid_isis_mtid.json`](../testdata/injection_cases/bgp_ls/srv6_sid_isis_mtid.json)):

```json
{
  "address_family": "bgp-ls",
  "action": "announce",
  "next_hops": ["fd00:100::2"],
  "nlri": {
    "protocol_id": "isis-level-2",
    "instance_id": "0",
    "link_state": {
      "kind": "srv6_sid",
      "local_node": {
        "autonomous_system": 65000,
        "igp_router_id": {"kind": "isis-system-id", "value": "0000.0000.0001"}
      },
      "descriptors": {
        "sid": "2001:db8:1::1",
        "multi_topology_id": 7
      }
    },
    "attributes": {
      "endpoint_behavior": 1,
      "flags": 0,
      "algorithm": 0,
      "sid_structure": {
        "locator_block_length": 32,
        "locator_node_length": 16,
        "function_length": 16,
        "argument_length": 0
      }
    }
  },
  "origin": "igp",
  "local_pref": 100
}
```

The optional `multi_topology_id` is encoded as TLV 263 in the SRv6 SID
descriptor. For interoperability with the XR version used in the testbed, the
encoder emits TLV 263 before the SID Information TLV 518. The lab verified
that MT-ID 7 is accepted and shown as `Multi-Topology: 0x0007`; the earlier
SID-first ordering was rejected by that XR parser. Omit the field when it is
not needed. For the Direct and BGP EPE fixtures, the default MT-ID is omitted.

To inject one of these requests, POST its fixture file to `/v1/routes`. For
example:

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data-binary @testdata/injection_cases/bgp_ls/srv6_sid_isis_mtid.json
```

On the peer, inspect the SRv6 SID NLRI details. The SID and optional MT-ID
appear under `SRv6 SID Descriptor`; endpoint behavior and SID structure appear
under `Link-state`. For BGP EPE, check the PeerNode SID TLV as well. IOS XR may
display the standardized type 1251 as `Unknown Attr` on some releases even
though the received wire data contains the defined PeerNode SID TLV.

#### SR Policy Candidate Path NLRI

Use `link_state.kind: "sr_policy_candidate_path"` to advertise an SR Policy
candidate path as BGP-LS information. This is the BGP-LS NLRI type 5 defined by
[RFC 9857](https://www.rfc-editor.org/rfc/rfc9857.html); set the top-level
`protocol_id` to `segment-routing` (protocol ID 9). The top-level
`instance_id` is the BGP-LS NLRI identifier.

For a headend-produced advertisement, `local_node` identifies the headend.
The fixtures include its BGP router ID and an IPv4 local router ID. Supply at
least one of `ipv4_router_id_local` or `ipv6_router_id_local`; the BGP router
ID is also required when the headend is the BGP-LS producer. The
`candidate_path` descriptor contains the protocol origin, endpoint, color,
originator AS and address, and discriminator. Its `flags` use bit `0x80` for
an IPv6 endpoint and bit `0x40` for an IPv6 originator address; the flags must
match the address families.
The `protocol_origin` values used by the fixtures are `1` for PCEP and `3` for
local configuration; `2` identifies BGP SR Policy. Values `10`, `20`, and `30`
identify those origins when the BGP-LS producer is a PCE.

The `attributes` object can carry the candidate-path state and name, policy
name, MPLS or SRv6 Binding SID, path constraints, and one or more segment
lists. Segment and segment-list `flags` are 16-bit masks represented as JSON
integers. For example, the MPLS fixture uses segment-list flags `0x7000`
(explicit, computed, verified), while the SRv6 fixture adds `0x8000` to select
the SRv6 data plane. Segment flags `0xe000` indicate an included, explicitly
provisioned SID that passed verification. Binding SID flags mark the
allocated MPLS or SRv6 BSID (`0x4000` for the MPLS BSID and `0x8000` for the
SRv6 BSID in these examples).

For segment types that carry a descriptor in addition to the SID,
`value_hex` supplies those descriptor bytes in hexadecimal. In the SRv6
fixture, Type 9 uses it for the 16-byte IPv6 node global address; `value` is
the SRv6 SID. The values may happen to match in the example, but they are
separate fields with separate meanings.

**MPLS candidate path** (from
[`sr_policy_mpls.json`](../testdata/injection_cases/bgp_ls/sr_policy_mpls.json))
advertises endpoint `192.0.2.9`, color 100, labels 16001 and 16002, and
allocated BSID 24001. **SRv6 candidate path** (from
[`sr_policy_srv6.json`](../testdata/injection_cases/bgp_ls/sr_policy_srv6.json))
advertises IPv6 endpoint `2001:db8:ffff::9`, color 200, two Type 9 segments,
and BSID `2001:db8:100::100`.

Both fixtures were accepted by the test XR router and their fields appeared
in `show bgp link-state link-state ... detail`. XR displayed the SR Segment
List Identifier TLV (type 1217, identifier 7) as `Unknown Attr`, including its
complete TLV bytes, while decoding the rest of the SRv6 path. Type 1217 is
standardized by RFC 9857; this output is a display/decoder limitation on the
tested XR image.

Post either complete fixture with the usual route endpoint:

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data-binary @testdata/injection_cases/bgp_ls/sr_policy_mpls.json

curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data-binary @testdata/injection_cases/bgp_ls/sr_policy_srv6.json
```

These advertisements report candidate-path state through BGP-LS. They do not
configure or activate an SR Policy in the router's forwarding plane; policy
signaling and forwarding behavior require the corresponding SR Policy
mechanisms and configuration.

## 8. IPv4 and IPv6 unicast examples

### Advertise IPv4 unicast

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "ipv4/unicast",
    "action": "announce",
    "nlri": {
      "prefix": "203.0.113.0/24"
    },
    "next_hops": ["192.0.2.25"],
    "origin": "igp",
    "local_pref": 100,
    "communities": ["65137:100"]
  }'
```

### Withdraw IPv4 unicast

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "ipv4/unicast",
    "action": "withdraw",
    "nlri": {
      "prefix": "203.0.113.0/24"
    }
  }'
```

### Advertise IPv6 unicast

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "ipv6/unicast",
    "action": "announce",
    "nlri": {
      "prefix": "2001:db8:100::/48"
    },
    "next_hops": ["2001:db8::25"],
    "origin": "igp",
    "local_pref": 100
  }'
```

### Withdraw IPv6 unicast

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "ipv6/unicast",
    "action": "withdraw",
    "nlri": {
      "prefix": "2001:db8:100::/48"
    }
  }'
```

## 9. VPNv4 and VPNv6 examples

VPN NLRIs require:

- one or more MPLS labels;
- a Route Distinguisher (RD); and
- a VPN prefix.

The last label must have `is_bos: true`. Label values are 20-bit values from
`0` through `1048575`; `exp` is from `0` through `7`.

The examples use:

- RD `10.169.21.121:30`;
- route target `65137:30`;
- VPN label `524286`; and
- LOCAL_PREF `100` for iBGP.

### Advertise VPNv4

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "vpnv4",
    "action": "announce",
    "nlri": {
      "labels": [
        {"value": 524286, "exp": 0, "is_bos": true}
      ],
      "rd": "10.169.21.121:30",
      "prefix": "11.24.0.0/16"
    },
    "next_hops": ["41.41.41.41"],
    "origin": "igp",
    "local_pref": 100,
    "extended_communities": [
      {
        "type": "route_target",
        "format": "two_octet_as",
        "asn": 65137,
        "local": 30
      }
    ]
  }'
```

### Withdraw VPNv4

The withdrawal must use the same RD, label stack, prefix, and Path-ID (when
applicable) as its advertisement. The next hop is not included.

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "vpnv4",
    "action": "withdraw",
    "nlri": {
      "labels": [
        {"value": 524286, "exp": 0, "is_bos": true}
      ],
      "rd": "10.169.21.121:30",
      "prefix": "11.24.0.0/16"
    }
  }'
```

### Advertise VPNv6

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "vpnv6",
    "action": "announce",
    "nlri": {
      "labels": [
        {"value": 524286, "exp": 0, "is_bos": true}
      ],
      "rd": "10.169.21.121:30",
      "prefix": "fd02:11:5798:ffff::a/128"
    },
    "next_hops": ["::ffff:41.41.41.41"],
    "origin": "igp",
    "local_pref": 100,
    "extended_communities": [
      {
        "type": "route_target",
        "format": "two_octet_as",
        "asn": 65137,
        "local": 30
      }
    ]
  }'
```

### Withdraw VPNv6

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '{
    "address_family": "vpnv6",
    "action": "withdraw",
    "nlri": {
      "labels": [
        {"value": 524286, "exp": 0, "is_bos": true}
      ],
      "rd": "10.169.21.121:30",
      "prefix": "fd02:11:5798:ffff::a/128"
    }
  }'
```

## 10. Extended communities

### Route Target and Site of Origin

Typed Route Target example:

```json
{
  "type": "route_target",
  "format": "two_octet_as",
  "asn": 65137,
  "local": 30
}
```

Typed Site of Origin uses the same fields with `"type": "site_of_origin"`.
Supported formats are:

- `two_octet_as`: 16-bit ASN and 32-bit local value;
- `four_octet_as`: 32-bit ASN and 16-bit local value; and
- `ipv4`: an `ipv4` field and a 16-bit local value.

### Raw extended communities

For an extended community without a typed API representation, supply its two
type bytes and exactly six value bytes:

```json
{
  "type": "raw",
  "type_high": 64,
  "type_low": 4,
  "value_hex": "fe714c0f0d18"
}
```

This specific example is the IOS XR-compatible, non-transitive Link Bandwidth
community for AS 65137 and 300 Mbps. The bandwidth is represented in bytes per
second as an IEEE-754 binary32 value. Useful tested values are:

| Bandwidth | `value_hex` for AS 65137 |
|---|---|
| 100 Mbps | `fe714b3ebc20` |
| 300 Mbps | `fe714c0f0d18` |

For IOS XR in this test environment, use `type_high: 64` (`0x40`) and
`type_low: 4` (`0x04`). With `type_high: 0`, the tested XR release displayed
the value as an unrecognized raw community rather than `LB:65137:...`.

## 11. ADD-PATH

ADD-PATH is needed when the same AFI/SAFI NLRI must be advertised more than
once with different paths. Start bgpinjector with the desired families:

```bash
./bgpinjector \
  --speaker-address=192.0.2.1:179 \
  --local-address=25.25.25.5 \
  --local-as=65137 \
  --router-id=25.25.25.5 \
  --api-address=127.0.0.1:8080 \
  --next-hop-mode=preserve \
  --add-path-send-families=vpnv4,vpnv6 \
  --rate=100 \
  --v=5
```

The router must advertise ADD-PATH **receive** for those families. Confirm
successful negotiation in `/v1/session`:

```json
"negotiated_add_path_send_families": [
  "vpnv4:send",
  "vpnv6:send"
]
```

When ADD-PATH send is negotiated for a family:

- every announcement and withdrawal in that family must include `path_id`;
- the withdrawal must use the same Path-ID as the advertisement; and
- omitting `path_id` causes the API to reject the request.

When ADD-PATH is not negotiated, supplying `path_id` is also rejected.

Example VPNv4 advertisement fragment:

```json
{
  "address_family": "vpnv4",
  "action": "announce",
  "path_id": 1,
  "nlri": {
    "labels": [{"value": 524286, "exp": 0, "is_bos": true}],
    "rd": "10.169.21.121:30",
    "prefix": "11.24.0.0/16"
  },
  "next_hops": ["41.41.41.41"],
  "origin": "igp",
  "local_pref": 100,
  "extended_communities": [
    {
      "type": "route_target",
      "format": "two_octet_as",
      "asn": 65137,
      "local": 30
    }
  ]
}
```

## 12. SRv6 L3 Service Prefix-SID

For VPNv4 over an IPv6 next hop, confirm that `/v1/session` reports VPNv4 in
`negotiated_families` and `vpnv4->ipv6` in
`negotiated_extended_next_hop_mappings`. A typed SRv6 L3 Service Prefix-SID
request has this form. Include `path_id` only if ADD-PATH send is negotiated
for that family; when it is not negotiated, omit `path_id`. The example below
uses VPN-label transposition, so the label and SID Structure values must remain
consistent.

```json
{
  "address_family": "vpnv4",
  "action": "announce",
  "nlri": {
    "labels": [{"value": 917568, "exp": 0, "is_bos": true}],
    "rd": "10.65.1.5:6",
    "prefix": "66.38.57.36/32"
  },
  "next_hops": ["fd04:b400::108"],
  "origin": "igp",
  "local_pref": 100,
  "prefix_sid": {
    "tlvs": [{
      "type": 5,
      "srv6_service": {
        "sub_tlvs": [{
          "type": 1,
          "sid_information": {
            "sid": "fc04:b400:108::",
            "endpoint_behavior": 63,
            "sub_sub_tlvs": [{
              "type": 1,
              "sid_structure": {
                "locator_block_length": 32,
                "locator_node_length": 16,
                "function_length": 16,
                "argument_length": 0,
                "transposition_length": 16,
                "transposition_offset": 48
              }
            }]
          }
        }]
      }
    }]
  }
}
```

### Typed manipulation boundaries

The typed form constructs valid RFC 9252 framing and lengths. It supports:

- SRv6 L3 Service TLV type `5`;
- SID Information Sub-TLV type `1`;
- SID Structure Sub-Sub-TLV type `1`;
- multiple SID Information entries in caller-supplied order;
- changes to the SID, endpoint behavior, and all six SID Structure fields; and
- unknown nested types supplied as raw base64 values.

Typed validation requires a native IPv6 SID, zero currently undefined flags,
valid SID Structure arithmetic, zero SID bits in the transposed range, and
zero SID bits following the declared structure. For VPN routes, transposition
length must also fit the function and the 20-bit VPN label. The transposed
value occupies the high-order label bits; unused low-order label bits must be
zero.

Changing `transposition_length`, `transposition_offset`, or function-related
fields may require a corresponding VPN-label change. Such a request is not a
Prefix-SID-only update unless the existing label remains valid. With the
example `[32,16,16,0]` structure and full 16-bit function transposition, the
base SID's function field remains zero; changing `fc04:b400:108::` to
`fc04:b400:109::` changes only the 48-bit locator portion.

If Prefix-SID validation, route-context validation, or marshalling fails while
constructing the UPDATE, bgpinjector rejects the complete UPDATE and does not
send it; it does not silently omit path attribute 40. `/v1/routes` queues work
asynchronously, so an HTTP `202` means the request was accepted into the queue,
not necessarily that UPDATE construction and transmission succeeded. Check
injector errors/statistics and the router's detailed BGP route.

### Raw manipulation boundaries

At each extensibility boundary, `value` is a JSON base64 string containing
only that TLV's value bytes. The enclosing type and two-octet length are added
by bgpinjector. For example, this is the raw equivalent of the typed service
data above:

```json
"prefix_sid": {
  "tlvs": [{
    "type": 5,
    "value": "AAEAHgD8BLQAAQgAAAAAAAAAAAAAAAA/AAEABiAQEAAQMA=="
  }]
}
```

Use typed fields for normal valid advertisements. Use nested raw values when
testing unknown Sub-TLV or Sub-Sub-TLV types, non-zero reserved or flag fields,
or semantic values intentionally outside the typed policy. Raw nested values
must still have structurally consistent TLV boundaries. Typed marshalling
always calculates lengths, so intentionally malformed headers or lengths
cannot be produced through `/v1/routes`; use a complete pre-encoded UPDATE via
`/v1/updates/raw` for those negative tests.

To update only Prefix-SID, post a second announcement without withdrawing the
first. Keep the address family, Path ID (when used), RD, prefix, label, next
hop, origin, local preference, and communities unchanged. Change only the
desired valid field inside `prefix_sid`, then verify that the router retains
one path and shows the new SID information.

### Verified IOS XR uSID test-bed case

The lab fixture at
[`injection_cases/srv6_prefix_sid_pe2`](../injection_cases/srv6_prefix_sid_pe2/README.md)
announces these VPNv4 and VPNv6 routes with PE2's IPv6 BGP next hop
`fc00::12` and the `CUST` route target `1:1`:

| Family | Test prefix | RD | Service SID | Endpoint behavior |
| --- | --- | --- | --- | --- |
| VPNv4 | `198.51.100.101/32` | `65001:901` | `fcbb:bb00:12:e002::` | uDT4 (63) |
| VPNv6 | `2001:db8:100::101/128` | `65001:902` | `fcbb:bb00:12:e003::` | uDT6 (62) |

The SID Structure is `32/16/16/0` (locator block/node/function/argument), with
transposition length and offset both zero. The VPN label is Implicit NULL
(value `3`). These are uSID service behaviors; do not replace their behavior
codes with the ordinary End.DT4 or End.DT6 values. `fc00::12` is the BGP next
hop, not either service SID.

For this lab session, ADD-PATH is not negotiated, so the fixture omits
`path_id`. The API rejects a supplied `path_id` when ADD-PATH send is not
negotiated, and requires one when it is negotiated. The fixture's
[`inject_routes.sh`](../injection_cases/srv6_prefix_sid_pe2/inject_routes.sh)
supports both announcement and withdrawal.

On IOS XR, the received BGP detail showed `PSID-Type:L3`, the expected SID,
behavior, label, route target, and SID Structure. PE1 imported both routes into
`CUST`; its route details showed `SRv6 Headend: H.Encaps.Red [f3216]` with the
corresponding service SID in the SID list. After withdrawal, the route was no
longer in the VRF routing table. The test prefixes are documentation ranges,
so they validate BGP/SRv6 route programming but are not ping destinations. This
Prefix-SID test also does not signal or select an SR Policy.

## 13. Batch requests

Post a JSON array to queue multiple updates:

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/routes' \
  -H 'Content-Type: application/json' \
  --data '[
    {
      "address_family": "ipv4/unicast",
      "action": "announce",
      "nlri": {"prefix": "203.0.113.0/24"},
      "next_hops": ["192.0.2.25"],
      "origin": "igp"
    },
    {
      "address_family": "ipv4/unicast",
      "action": "announce",
      "nlri": {"prefix": "198.51.100.0/24"},
      "next_hops": ["192.0.2.25"],
      "origin": "igp"
    }
  ]'
```

Keep batches reasonably small. A batch is not transactional: if processing a
later item fails, earlier items may already have entered the queue. The whole
HTTP request must also remain below the 1 MiB limit.

## 14. Raw BGP UPDATE injection

Advanced users can submit a complete BGP UPDATE encoded as hexadecimal or
base64:

```bash
curl --fail-with-body --silent --show-error \
  -X POST 'http://127.0.0.1:8080/v1/updates/raw' \
  -H 'Content-Type: application/json' \
  --data '{
    "encoding": "hex",
    "data": "ffffffffffffffffffffffffffffffff..."
  }'
```

Raw injection bypasses normalized route construction and next-hop rewriting.
The endpoint currently gates the AFI/SAFI but does not extract and enforce
ADD-PATH or Extended Next Hop requirements from the raw bytes. The caller is
responsible for producing a complete, valid UPDATE that matches all negotiated
capabilities, including ADD-PATH Path-IDs. Prefer `/v1/routes` unless exact
wire control is required.

## 15. Verification on the router

Always verify at more than one layer:

1. Neighbor state and negotiated capabilities.
2. Received BGP path for the exact AFI/SAFI.
3. Best-path selection and alternate/additional paths.
4. VRF import based on Route Target.
5. RIB and FIB installation.
6. Next-hop recursion and MPLS label programming where relevant.

Typical IOS XR commands include:

```text
show bgp neighbors <injector-source-address>
show bgp ipv4 unicast
show bgp ipv6 unicast
show bgp vpnv4 unicast
show bgp vpnv6 unicast
show route vrf <vrf-name>
show route vrf <vrf-name> ipv6
```

Use platform-specific detail commands to inspect RD, Path-ID, communities,
next hop, VPN label, and whether the path was accepted or rejected.

## 16. Troubleshooting

### The BGP session does not establish

- Check `curl http://127.0.0.1:8080/v1/session` and inspect `last_error`.
- Confirm TCP/179 reachability and firewall rules.
- Confirm `local_address` and `local_endpoint` in `/v1/session` match the
  router's configured neighbor address.
- Confirm the address passed to `--local-address` exists in the process or
  container network namespace.
- Confirm local and remote AS configuration.
- Confirm the router does not require an unsupported TCP MD5 password.
- In Docker, check NAT, host networking, and the source seen by the router.
- Review logs with `--v=5` or `docker logs bgpinjector`.

### `/readyz` returns 503

The API process is running, but BGP is not established. Do not post routes
until `/readyz` returns 200.

### The API returns 400

Read the JSON `error` field. Common causes are:

- the requested AFI/SAFI was not negotiated;
- an announcement has no usable next hop;
- the prefix does not match the selected family;
- VPN NLRI is missing a label or RD;
- the last MPLS label does not have `is_bos: true`;
- a required Path-ID is absent;
- a Path-ID was supplied without ADD-PATH negotiation; or
- an extended community has an invalid format or value length.

### The API returns 429

The local event queue is full. Reduce the submission rate, increase
`--queue-size` within safe memory limits, or wait for the queue to drain.

### The API accepts a route but it is absent on the router

- Compare `sent_updates` before and after the request.
- Confirm the correct family and capability negotiation.
- Check router received-route and policy-rejection views.
- Confirm route target import for VPN routes.
- Confirm the next hop is reachable.
- Check that ADD-PATH is configured in the correct direction.
- Look for malformed UPDATE or treat-as-withdraw logs on the router.

### Only one of two paths is visible

If both updates describe the same NLRI, enable ADD-PATH send on bgpinjector and
ADD-PATH receive on the router, then use a distinct `path_id` for each path.
Without negotiated ADD-PATH, a later advertisement replaces the earlier path.

## 17. API security

The current HTTP API has no authentication or TLS. Anyone who can reach it can
attempt to inject routes. Recommended practice:

- bind to `127.0.0.1` whenever possible;
- when remote access is necessary, restrict it with host firewall rules or an
  authenticated reverse proxy;
- never publish the API directly to an untrusted network; and
- do not store router credentials or BGP authentication material in API JSON.

## 18. Test cleanup checklist

Before ending a test:

1. Send matching withdrawals for every injected route.
2. Confirm the prefixes have disappeared from the router's BGP and VRF tables.
3. Check the RIB and FIB for stale entries.
4. Stop bgpinjector only after withdrawals have been transmitted.
5. Save the injector logs, route requests, session snapshot, and relevant router
   outputs when the test is intended to reproduce a defect.
