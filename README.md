# bgpinjector supplements

Practical guides, testbeds, and route-injection examples for using **bgpinjector** in network labs.

`bgpinjector` is a BGP speaker with an HTTP API. It establishes an outbound BGP session to a router and accepts route announcements and withdrawals over HTTP, making it useful for controlled interoperability tests, route-policy checks, and reproducing routing scenarios that are difficult to generate from a conventional host. The bgpinjector application itself is not part of this repository. This project documents how to run it and provides lab configurations and example requests that can be adapted to your environment.

## Start here

- Read the [bgpinjector User Guide](docs/user_guide.md) for standalone and Docker setup, session readiness, API use, route families, verification, and cleanup.
- Browse the [injection cases](injection_cases/) for ready-to-submit JSON requests, paired announcements and withdrawals, and notes about expected behavior.
- Explore the [testbeds](testbeds/) for Docker Compose labs and router configurations used to exercise selected cases.

## What you can explore

The materials cover several kinds of BGP testing:

- **BGP-LS:** Node, Link, IPv4/IPv6 Prefix, SRv6 SID, and SR Policy Candidate Path examples for IS-IS, OSPF, and BGP descriptors, including selected BGP-LS-VPN forms. See [BGP-LS fixtures](injection_cases/bgp_ls/README.md).
- **BGP-MUP:** IPv4 and IPv6 ISD, DSD, ST1, and ST2 route examples, with matching withdrawals and Prefix-SID variations. See [BGP-MUP fixtures](injection_cases/bgp_mup/README.md).
- **SRv6 VPN services:** VPNv4 and VPNv6 Prefix-SID examples using PE2 service SIDs, with an announcement/withdrawal helper. See [the PE2 injection case](injection_cases/srv6_prefix_sid_pe2/README.md).
- **GoBMP decoding:** BGP-LS attributes bundled into sample routes for manual validation through a BMP collector. See [GoBMP BGP-LS fixtures](injection_cases/gobmp/bgp_ls/README.md) and the [manual interoperability test plan](docs/gobmp_bgp_ls_manual_interoperability_test_plan.md).
- **Same-label VPN routes:** A helper and notes for injecting VPNv4/VPNv6 routes that share a VPN label. See [the same-label case](injection_cases/vpnv4_vpnv6_same_vpn_label/inject_vpn_test_routes.md).

The testbed collection includes a full BGP-LS XRd lab, an SRv6 VPNv4 lab, and a six-node SRv6 topology. Each directory has its own README or Compose files with topology-specific setup details. These are lab starting points: check each testbed's prerequisites and configuration status before bringing it up.

## Typical workflow

1. Choose a testbed or connect bgpinjector to a router you control. Confirm IP reachability to TCP/179 and configure the peer with the injector's actual source address and ASN.
2. Start bgpinjector with the desired BGP peer, local ASN, router ID, and API listen address. Use the supplied binary or container image for your environment.
3. Check `/healthz`, then `/readyz` and `/v1/session`. Inject only after the session is established and the required address family and capabilities are negotiated.
4. Adapt a fixture's next hop and other lab-specific values, then POST it to `/v1/routes`. A `202 Accepted` response means the request entered the local queue; verify transmission and route acceptance on the peer.
5. Send the matching withdrawal and confirm the route is removed before ending the test.

For example, after starting bgpinjector with its API on `127.0.0.1:8080`:

```sh
curl --fail-with-body --silent --show-error \
  -X POST http://127.0.0.1:8080/v1/routes \
  -H 'Content-Type: application/json' \
  --data-binary @injection_cases/bgp_ls/node_isis.json
```

Fixture values such as next hops, route distinguishers, labels, route targets, and SIDs are specific to their example labs. Review and adapt them before use. Refer to the [User Guide](docs/user_guide.md) for the complete startup, API, verification, and cleanup instructions.

## Important behavior and safety

bgpinjector sends real BGP UPDATE messages. Use an isolated lab or restrictive import policy, verify the prefixes and attributes before injection, and keep corresponding withdrawals ready. The API queues updates asynchronously and does not guarantee that a peer accepted or installed a route. Check the peer's received BGP routes, policy results, RIB, and FIB as appropriate.

The injector is a route-generation tool, not a routing daemon or persistent RIB: it does not retain injected routes for replay after a session reset. Its HTTP API currently has no authentication or TLS, so keep it bound to loopback unless access is restricted by network controls or an authenticated proxy. See [API security and test cleanup](docs/user_guide.md#17-api-security).

## Repository map

```text
docs/             Setup guide and interoperability test plans
injection_cases/  API request fixtures, scripts, and case documentation
testbeds/         Docker Compose labs and router configuration examples
```

## Contributing examples

When adding an injection case, include enough context to make it reproducible: the address family and required peer capabilities, any assumptions about next hops or policy, an announcement and matching withdrawal where applicable, and notes describing how to verify the result. Keep lab-specific values clearly identified so readers know what to adapt.

