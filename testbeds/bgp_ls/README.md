# BGP-LS Full Lab Testbed

This Compose project provisions the complete physical topology from the supplied
[BGP-LS XRd lab guide](bgp-ls-xrd-lab-guide.md): **9 XRd control-plane
instances, one GoBMP collector, and one bgpinjector container**. It is intended
to measure whether the current Docker server can run the lab and to provide a
stable, explicit interface/address map for later BGP-LS, BGP-LS-VPN, SRv6, EPE,
and BMP work.

The current XR startup files focus on hostnames, management addressing, data
interface addressing, VLAN subinterfaces/VRFs for the two CE links, and
interface descriptions. RR1 also has a minimal BGP neighbor for bgpinjector
and a BMP client definition. They do not configure the complete
IS-IS/BGP/OSPF/SR protocol stack. The guide's XR CLI examples are
release-dependent and marked for verification; they have not been assumed to
be valid on every XRd image.

## Topology

```text
CE1 --L10-- PE1 --L1-- P1 ==L2/L3== P2 --L4-- PE2 --L5-- ASBR1 --L7-- EXT1
                              |                     |          |
                              L6 shared LAN          L11        L6
                              |                     |          |
                              +---------------------+----------+
                              |
                            P1 --L8-- RR1 --L9/BMP-- GoBMP
                                      |
                                      +-- test-only link -- bgpinjector
```

L6 is one shared Ethernet segment among P1, P2, and ASBR1. L10 and L11 are
802.1Q trunks. Each trunk carries VLAN 100 (VRF A) and VLAN 200 (VRF B); the
IPv4 and IPv6 addresses intentionally overlap between those VRFs. The extra
`injector-rr1` network gives bgpinjector a dedicated test BGP link and does not
change the nine-router topology in the guide.

## Link and XR interface map

Interface names are pinned with Compose `interface_name` plus each XRd
`XR_INTERFACES` variable. Each generated XR interface description names the
remote router and its peer interface.

| Link | Endpoint A | Endpoint B | Configured addresses |
|---|---|---|---|
| L1 | PE1 Gi0/0/0/0 | P1 Gi0/0/0/0 | 10.1.1.1/30, fd00:1:1::1/64 ↔ 10.1.1.2/30, fd00:1:1::2/64 |
| L2 | P1 Gi0/0/0/1 | P2 Gi0/0/0/0 | 10.1.2.1/30, fd00:1:2::1/64 ↔ 10.1.2.2/30, fd00:1:2::2/64 |
| L3 | P1 Gi0/0/0/2 | P2 Gi0/0/0/1 | 10.1.3.1/30, fd00:1:3::1/64 ↔ 10.1.3.2/30, fd00:1:3::2/64 |
| L4 | P2 Gi0/0/0/2 | PE2 Gi0/0/0/0 | 10.1.4.1/30, fd00:1:4::1/64 ↔ 10.1.4.2/30, fd00:1:4::2/64 |
| L5 | PE2 Gi0/0/0/1 | ASBR1 Gi0/0/0/1 | 10.1.5.1/30, fd00:1:5::1/64 ↔ 10.1.5.2/30, fd00:1:5::2/64 |
| L6 | P1 Gi0/0/0/3, P2 Gi0/0/0/3, ASBR1 Gi0/0/0/0 | Shared LAN | 10.1.6.2/.3/.5/24; fd00:1:6::2/::3/::5/64 |
| L7 | ASBR1 Gi0/0/0/2 | EXT1 Gi0/0/0/0 | 172.16.57.1/30, fd00:172:57::1/64 ↔ 172.16.57.2/30, fd00:172:57::2/64 |
| L8 | P1 Gi0/0/0/4 | RR1 Gi0/0/0/0 | 10.1.8.1/30, fd00:1:8::1/64 ↔ 10.1.8.2/30, fd00:1:8::2/64 |
| L9 | RR1 Gi0/0/0/1 | GoBMP eth1 | 192.168.100.1/24 ↔ 192.168.100.10/24, TCP/5000 |
| L10 trunk | PE1 Gi0/0/0/1 | CE1 Gi0/0/0/0 | VLAN 100 and 200; each VRF uses 192.168.11.1/.2/30 and fd00:11::1/::2/64 |
| L11 trunk | PE2 Gi0/0/0/2 | CE2 Gi0/0/0/0 | VLAN 100 and 200; each VRF uses 192.168.12.1/.2/30 and fd00:12::1/::2/64 |
| Injector link | RR1 Gi0/0/0/2 | bgpinjector eth1 | 192.0.2.1/24, fd00:100::1/64 ↔ 192.0.2.2/24, fd00:100::2/64; Docker gateways .254 and ::ffff |

Docker's link networks use separate dummy `172.30.N.0/24` subnets. XR interface
addresses above are configured inside XR and do not reuse the Docker bridge
subnets. The BMP network uses `192.168.100.0/24` with gateway `.254` so RR1 can
own `.1` and GoBMP `.10` without a bridge-address collision. The injector test
network explicitly reserves `.254` and `::ffff` as its Docker gateways so RR1's
`.1` and `::1` addresses remain available.

## Node addressing

| Node | Loopback IPv4 | Loopback IPv6 | Docker management IPv4 |
|---|---|---|---|
| PE1 | 10.0.0.1/32 | fd00::1/128 | 172.20.0.11 |
| P1 | 10.0.0.2/32 | fd00::2/128 | 172.20.0.12 |
| P2 | 10.0.0.3/32 | fd00::3/128 | 172.20.0.13 |
| PE2 | 10.0.0.4/32 | fd00::4/128 | 172.20.0.14 |
| ASBR1 | 10.0.0.5/32 | fd00::5/128 | 172.20.0.15 |
| RR1 | 10.0.0.6/32 | fd00::6/128 | 172.20.0.16 |
| EXT1 | 10.0.0.7/32 | fd00::7/128 | 172.20.0.17 |
| CE1 | VRF A/B: 10.11.0.1/32 | VRF A/B: fd00:11:ff::1/128 | 172.20.0.18 |
| CE2 | VRF A/B: 10.12.0.1/32 | VRF A/B: fd00:12:ff::1/128 | 172.20.0.19 |
| bgpinjector | 10.0.0.99 BGP router ID | fd00:100::2 on test link | 172.20.0.20 |

CE1/CE2 also have extra VRF loopbacks for prefix tests: CE1 `10.11.1.1/24`
and CE2 `10.12.1.1/24`, duplicated across their A and B VRFs.

## Files

- `docker-compose.yml`: all 11 containers, all links, stable container
  interfaces, host-preparation service, and named XR storage volumes.
- `pe1.cfg`, `p1.cfg`, `p2.cfg`, `pe2.cfg`, `asbr1.cfg`, `rr1.cfg`, `ext1.cfg`,
  `ce1.cfg`, `ce2.cfg`: XR hostnames, interface addresses/descriptions and
  required VRF/subinterface address scaffolding.
- `BUILD.bazel`: exposes the testbed files as a Bazel filegroup.

## Prerequisites and resource evaluation

- Docker Engine with Compose v2 and a Linux host suitable for XRd.
- An XRd image accessible to the Docker daemon. Default:
  `sbezverk/xrd-control-plane:26.2.1`; override using `XR_IMAGE`.
- `/dev/fuse`, `/dev/net/tun`, bridge netfilter support, and enough CPU, memory,
  and disk for nine XRd control planes plus GoBMP and bgpinjector.
- GoBMP defaults to `docker.io/sbezverk/gobmp:latest`; override with
  `GOBMP_IMAGE`.
- bgpinjector defaults to `docker.io/sbezverk/bgpinjector:srv6`; override with
  `BGPINJECTOR_IMAGE`. The running image may predate normalized BGP-LS support;
  this testbed's address and resource layout is ready for that work, but the
  image must support AFI 16388 before BGP-LS route injection can be exercised.

Check rendered service count and host resource state before starting XRd:

```sh
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml config --services
docker info
df -h
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml config --quiet
```

After startup, inspect actual resource consumption rather than relying on a
hardware estimate:

```sh
docker stats --no-stream
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml ps
```

XRd host preparation is a privileged one-shot service, following the repository's
existing `srv6_6_nodes` pattern. It changes host bridge, IPv6, inotify, and
socket-buffer sysctls. Review the `xrd-host-prep` service before starting the
lab. Docker Compose validation does not run that service or change the host.

## Start, inspect, and stop

Run commands from the repository root:

```sh
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml config --quiet
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml up -d
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml ps
docker stats --no-stream
```

The first `up` starts host preparation, GoBMP, all nine XRd nodes, and
bgpinjector. XRd boot and config application take several minutes. Follow logs
with:

```sh
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml logs -f pe1 p1 p2 pe2 asbr1 rr1 ext1 ce1 ce2 gobmp bgpinjector
```

SSH ports are PE1 2221, P1 2222, P2 2223, PE2 2224, ASBR1 2225, RR1 2226,
EXT1 2227, CE1 2228, and CE2 2229. Use the credentials for the selected XRd
image; no credentials are added to these configs. Each host port can be
overridden with a variable such as `RR1_SSH_PORT=32226`; the matching variables
are named `PE1_SSH_PORT`, `P1_SSH_PORT`, `P2_SSH_PORT`, `PE2_SSH_PORT`,
`ASBR1_SSH_PORT`, `RR1_SSH_PORT`, `EXT1_SSH_PORT`, `CE1_SSH_PORT`, and
`CE2_SSH_PORT`.

GoBMP writes JSON Lines to
`testdata/testbeds/bgp_ls/output/gobmp.jsonl`:

```sh
tail -f testdata/testbeds/bgp_ls/output/gobmp.jsonl
```

bgpinjector's HTTP API is published on host port 18080 by default; override it
with `BGPINJECTOR_API_PORT`.

Stop containers and preserve XRd state:

```sh
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml down
```

Remove containers and reset all persisted XRd state:

```sh
docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml down -v
```

## Address/interface checks

After boot, check interfaces on each XRd node:

```text
show ipv4 interface brief
show ipv6 interface brief
show interfaces description
```

The interface description on each endpoint should name the remote router and
remote XR interface from the link table. Validate both ends before adding
routing protocols. For the trunks, verify both VLAN subinterfaces and the
corresponding VRF assignment. The CE-A and CE-B addresses intentionally match
inside separate VRFs.

## Troubleshooting a container start failure

If Docker reports `failed to set up container networking: Address already in
use` while starting RR1, the short error line does not identify the resource
that conflicted. One common cause is a host port already bound by another
process or container. RR1's SSH mapping defaults to host port 2226; inspect it
and retry on another host port:

```sh
ss -ltnp | grep ':2226 '
RR1_SSH_PORT=32226 docker compose -f testdata/testbeds/bgp_ls/docker-compose.yml up -d rr1
```

The Compose file makes every SSH host port configurable. If a non-port network
endpoint is the cause, get the expanded error from `docker compose up rr1` and
check the reported network/IP against `docker network inspect bgp_ls_bmp` and
`docker network inspect bgp_ls_injector-rr1`. The pasted summary alone is not
enough to distinguish a host-port bind conflict from an address/interface
conflict.

## Protocol configuration status

The supplied lab guide defines a larger protocol plan: multi-level IS-IS,
BGP-LS SAFI 71, SAFI 72 feasibility and VRF OSPF, SR-MPLS, Flex-Algo, SRv6,
BGP EPE, and BMP. Those routing features are intentionally not enabled in this
resource-sizing/addressing pass. The startup configs establish the physical
interface map and addressing first. Add protocol configuration after confirming
that all nine XRd containers remain stable on the target server and that the
interface map is correct for its image/version.
