# BGP-LS Lab Guide: SAFI 71, SRv6 Extensions and SAFI 72 (BGP-LS-VPN) on XRd

This guide is built from a design discussion. It has not been checked against Cisco documentation or a running XRd image. Lines marked **Verify** are syntax or features not confirmed for your XRd release. Run Phase 0 before anything else, because it decides whether XRd can originate SAFI 72 at all.

> **Revision note (OSPF fixes):** `distribute link-state` is a **process-level** command under `router ospf` / `router ospfv3` on XR (options: `instance-id`, `throttle`, `follow-on`). It is not accepted in VRF mode. Because a process takes only one instance-id, PE1/PE2 now run **one OSPFv2 and one OSPFv3 process per VRF** (`VPN-A`, `VPN-B`, `VPN6-A`, `VPN6-B`) so each VRF/protocol keeps its own identifier (200/201/300/301). BGP `redistribute` lines, Phase 0 checks F2/F3, the instance plan, T-V11 and troubleshooting were updated to match. `address-family link-state vpn` (SAFI 72) lines are intentionally unchanged pending a check on a newer IOS XR image.

---

## 1. Objectives

| # | Objective | Extension |
|---|---|---|
| O1 | Export multi-level IS-IS LSDB (L1 areas + L2) into BGP-LS | SAFI 71 base (RFC 9552) |
| O2 | Carry SR-MPLS SIDs, Flex-Algo definitions and TE attributes | SR / Flex-Algo |
| O3 | Carry SRv6 locators, End/End.X/LAN End.X SIDs | RFC 9514 |
| O4 | Carry BGP EPE Peer SIDs (MPLS and SRv6) | RFC 9086 / RFC 9514 |
| O5 | Originate VRF OSPF LSDBs as BGP-LS-VPN with RD and RT | SAFI 72 |
| O6 | Verify gobmp decodes O1 to O5 correctly from BMP | Collector |

---

## 2. Topology

```
  CE1 (VRF A + B, OSPF)                                 CE2 (VRF A + B, OSPF)
   │L10 (.100 / .200)                                     │L11 (.100 / .200)
 ┌─┴──┐  L1  ┌────┐ L2 (a) ┌────┐  L4  ┌────┐  L5  ┌─────┐  L7 eBGP v4+v6  ┌────┐
 │PE1 ├──────┤ P1 ╞════════╡ P2 ├──────┤PE2 ├──────┤ASBR1├─────────────────┤EXT1│ AS 65001
 └────┘      └┬─┬─┘ L3 (b) └─┬──┘      └────┘ flap └──┬──┘                 └────┘
          L8  │ │            │                        │
       ┌──────┘ └────────────┴──── L6 LAN (broadcast) ┘
    ┌──┴─┐
    │RR1 │  RR: link-state, link-state-vpn*, vpnv4, vpnv6
    └──┬─┘
       │L9 BMP
    ┌──┴───┐
    │gobmp │
    └──────┘
```

There are 9 XRd Control Plane containers plus gobmp. To trim to 8 XRd nodes, drop CE2. You keep one VPN LSDB per VRF.

### Area and AS layout

| Domain | Members |
|---|---|
| IS-IS CORE L1 area 49.0001 | PE1, P1 |
| IS-IS CORE L1 area 49.0002 | P2, PE2, ASBR1 |
| IS-IS CORE L2 backbone | P1, P2, ASBR1, RR1 |
| OSPFv2/v3 VRF CUST-A | PE1↔CE1, PE2↔CE2 (subif .100) |
| OSPFv2/v3 VRF CUST-B | PE1↔CE1, PE2↔CE2 (subif .200, overlapping addresses) |
| AS 65000 | All except EXT1 and CEs |
| AS 65001 | EXT1 |

---

## 3. Connection table

On point-to-point links, side A is .1 / ::1 and side B is .2 / ::2.

| Link | Side A | Side B | IPv4 | IPv6 | Protocol / metric | Purpose |
|---|---|---|---|---|---|---|
| L1 | PE1 Gi0/0/0/0 | P1 Gi0/0/0/0 | 10.1.1.0/30 | fd00:1:1::/64 | IS-IS L1, 10 | PE1 uplink |
| L2 | P1 Gi0/0/0/1 | P2 Gi0/0/0/0 | 10.1.2.0/30 | fd00:1:2::/64 | IS-IS L2, 10 (P1) / 15 (P2) | Core (a), asymmetric |
| L3 | P1 Gi0/0/0/2 | P2 Gi0/0/0/1 | 10.1.3.0/30 | fd00:1:3::/64 | IS-IS L2, 20 | Parallel link (b) |
| L4 | P2 Gi0/0/0/2 | PE2 Gi0/0/0/0 | 10.1.4.0/30 | fd00:1:4::/64 | IS-IS L1, 10 | PE2 uplink |
| L5 | PE2 Gi0/0/0/1 | ASBR1 Gi0/0/0/1 | 10.1.5.0/30 | fd00:1:5::/64 | IS-IS L1, 30 | **Flap link** |
| L6 | P1 Gi0/0/0/3 (.2), P2 Gi0/0/0/3 (.3), ASBR1 Gi0/0/0/0 (.5) | shared LAN | 10.1.6.0/24 | fd00:1:6::/64 (::2/::3/::5) | IS-IS L2 **broadcast**, 10 | Pseudonode, LAN Adj-SID, LAN End.X |
| L7 | ASBR1 Gi0/0/0/2 | EXT1 Gi0/0/0/0 | 172.16.57.0/30 | fd00:172:57::/64 | eBGP v4 + v6 | EPE (MPLS + SRv6) |
| L8 | P1 Gi0/0/0/4 | RR1 Gi0/0/0/0 | 10.1.8.0/30 | fd00:1:8::/64 | IS-IS L2, 100 | RR attachment |
| L9 | RR1 Gi0/0/0/1 (.1) | gobmp eth1 (.10) | 192.168.100.0/24 | fd00:100::/64 | none | BMP TCP/5000 |
| L10.100 | PE1 Gi0/0/0/1.100 | CE1 Gi0/0/0/0.100 | 192.168.11.0/30 | fd00:11::/64 | OSPF area 0, VRF CUST-A | VPN LSDB A1 |
| L10.200 | PE1 Gi0/0/0/1.200 | CE1 Gi0/0/0/0.200 | 192.168.11.0/30 | fd00:11::/64 | OSPF area 0, VRF CUST-B | VPN LSDB B1 (overlap) |
| L11.100 | PE2 Gi0/0/0/2.100 | CE2 Gi0/0/0/0.100 | 192.168.12.0/30 | fd00:12::/64 | OSPF area 0, VRF CUST-A | VPN LSDB A2 |
| L11.200 | PE2 Gi0/0/0/2.200 | CE2 Gi0/0/0/0.200 | 192.168.12.0/30 | fd00:12::/64 | OSPF area 0, VRF CUST-B | VPN LSDB B2 (overlap) |
| mgmt | All XRd MgmtEth0/RP0/CPU0/0 | | 172.20.0.0/24 | | none | Out-of-band SSH |

---

## 4. Node plan

| Node | Lo0 v4 / v6 | NET | IS-IS type | SR-MPLS SID (algo 0 / 128) | SRv6 locators (uSID f3216) |
|---|---|---|---|---|---|
| PE1 | 10.0.0.1 / fd00::1 | 49.0001.0000.0000.0001.00 | L1 | 16001 / 16101 | fcbb:bb00:1::/48, fcbb:bb01:1::/48 |
| P1 | 10.0.0.2 / fd00::2 | 49.0001.0000.0000.0002.00 | L1/L2 | 16002 / 16102 | fcbb:bb00:2::/48, fcbb:bb01:2::/48 |
| P2 | 10.0.0.3 / fd00::3 | 49.0002.0000.0000.0003.00 | L1/L2 | 16003 / 16103 | fcbb:bb00:3::/48, fcbb:bb01:3::/48 |
| PE2 | 10.0.0.4 / fd00::4 | 49.0002.0000.0000.0004.00 | L1 | 16004 / 16104 | fcbb:bb00:4::/48, fcbb:bb01:4::/48 |
| ASBR1 | 10.0.0.5 / fd00::5 | 49.0002.0000.0000.0005.00 | L1/L2 | 16005 / 16105 | fcbb:bb00:5::/48, fcbb:bb01:5::/48 |
| RR1 | 10.0.0.6 / fd00::6 | 49.0001.0000.0000.0006.00 | L2, overload | 16006 / none | fcbb:bb00:6::/48 |
| EXT1 | 10.0.0.7 / fd00::7 | none | none | none | none |
| CE1 | VRF A and B: 10.11.0.1 / fd00:11:ff::1 (same in both) | none | OSPF | none | none |
| CE2 | VRF A and B: 10.12.0.1 / fd00:12:ff::1 (same in both) | none | OSPF | none | none |

- **SRGB:** 16000–23999.
- **Flex-Algo 128:** metric-type delay, with the definition advertised by P1 and P2.
- **iBGP:** over IPv6 loopbacks to RR1 (fd00::6).

### VRF and BGP-LS instance plan

The instance-ids are lab-local values chosen for this guide (hundreds digit = domain: 1 core, 2 CUST-A, 3 CUST-B; last digit = protocol: 0 OSPFv2, 1 OSPFv3). They populate the BGP-LS NLRI Identifier field. Any values unique per IGP instance work.

`distribute link-state instance-id` is set at the **OSPF process level**, and a process takes one instance-id. Each VRF therefore gets its own OSPFv2 and OSPFv3 process on the PEs.

| VRF | RD PE1 | RD PE2 | RT | OSPFv2 process / instance-id | OSPFv3 process / instance-id | PE OSPF router-id |
|---|---|---|---|---|---|---|
| CUST-A | 10.0.0.1:100 | 10.0.0.4:100 | 65000:100 | `VPN-A` / 200 | `VPN6-A` / 201 | PE1 10.0.1.1, PE2 10.0.4.1 |
| CUST-B | 10.0.0.1:200 | 10.0.0.4:200 | 65000:200 | `VPN-B` / 300 | `VPN6-B` / 301 | PE1 10.0.1.1, PE2 10.0.4.1 |
| IS-IS CORE (global) | none | none | none | IS-IS instance-id 100 | | |

PE router-ids are deliberately identical across CUST-A and CUST-B. Only the RD tells them apart in SAFI 72.

### BGP-LS producer roles

| Node | Produces | SAFI |
|---|---|---|
| P1 | IS-IS L1 (49.0001) + L2 | 71 |
| P2 | IS-IS L1 (49.0002) + L2 | 71 |
| ASBR1 | BGP EPE Peer SIDs (protocol-ID BGP) | 71 |
| PE1, PE2 | VRF OSPFv2/v3 LSDBs for CUST-A and CUST-B | 72 |
| RR1 | Reflects all; exports to gobmp via BMP | 71 + 72 |

---

## 5. Phase 0: Feasibility gate (run first)

Bring up only PE1, P1 and RR1 with minimal config, then run these checks.

| # | Check | Command / action | Pass criterion | If it fails |
|---|---|---|---|---|
| F1 | XR offers a BGP-LS-VPN AF | `router bgp 65000` → `address-family link-state ?` | An option beyond `link-state` (for example `vpn`) is offered | XRd can't originate SAFI 72. Keep the topology and attach a SAFI 72-capable speaker to RR1 or the L9 segment |
| F2 | OSPFv2 process accepts BGP-LS distribution | `router ospf VPN-A` → `distribute link-state ?` (process level, **not** under `vrf`) | `instance-id`, `throttle`, `follow-on` offered | Same fallback as F1 |
| F2b | OSPFv2 VRF LSDB is exported | After Phase 4: `show ospf VPN-A vrf CUST-A database` vs. LS NLRIs from PE1 (`show bgp link-state link-state` on PE1 or gobmp) | VRF CUST-A nodes/links/prefixes appear with identifier 200 | Process-level export covers only the default VRF on this release. Same fallback as F1 |
| F3 | OSPFv3 process accepts it | `router ospfv3 VPN6-A` → `distribute link-state ?` (process level) | `instance-id`, `throttle`, `follow-on` offered | Run SAFI 72 v4-only |
| F3b | OSPFv3 VRF LSDB is exported | Same as F2b for `VPN6-A` / identifier 201 | VRF CUST-A OSPFv3 topology appears | Run SAFI 72 v4-only |
| F4 | BMP exports link-state AFs | After Phase 3, check that gobmp receives LS NLRIs | NLRIs visible | Check the XR release's BMP AF support |
| F5 | SRv6 EPE SIDs | `show bgp egress-engineering` on ASBR1 | SRv6 SIDs, not only labels | Test MPLS EPE only |
| F6 | SR-MPLS and SRv6 coexist | Commit both on one node | Both active | Drop SR-MPLS |

Note: under `router ospf … vrf` / `router ospfv3 … vrf`, `distribute ?` offers only `distribute-list in|out` (route filtering). That is unrelated to BGP-LS; do not use it here.

Record the XRd version (`show version`) with the results. Support may differ between releases.

---

## 6. Build

### 6.1 Host prerequisites

- **Image:** XRd Control Plane. BGP-LS needs no data-plane forwarding.
- **Resources:** run `host-check` from Cisco's `xrd-tools` repository to validate kernel, cgroups, inotify and memory limits for 9 instances. Size host RAM from Cisco's per-instance requirement for your release.
- **Docker networks:** use one Docker network per link. Give the networks **dummy IPAM subnets** (for example 172.30.N.0/24) that don't overlap lab addressing. Otherwise the host bridge takes .1 and collides with XR addresses. XR addressing is configured independently.
- **L9 `bmp` network:** use 192.168.100.0/24 with **gateway .254**, because RR1 uses .1. Give gobmp a static 192.168.100.10.

### 6.2 Docker network to interface mapping

| Network | Members (Linux → XR) |
|---|---|
| mgmt | All XRd: eth0 → MgmtEth0/RP0/CPU0/0 |
| l1 | PE1 eth1 → Gi0/0/0/0, P1 eth1 → Gi0/0/0/0 |
| l2 | P1 eth2 → Gi0/0/0/1, P2 eth1 → Gi0/0/0/0 |
| l3 | P1 eth3 → Gi0/0/0/2, P2 eth2 → Gi0/0/0/1 |
| l4 | P2 eth3 → Gi0/0/0/2, PE2 eth1 → Gi0/0/0/0 |
| l5 | PE2 eth2 → Gi0/0/0/1, ASBR1 eth2 → Gi0/0/0/1 |
| l6 | P1 eth4 → Gi0/0/0/3, P2 eth4 → Gi0/0/0/3, ASBR1 eth1 → Gi0/0/0/0 |
| l7 | ASBR1 eth3 → Gi0/0/0/2, EXT1 eth1 → Gi0/0/0/0 |
| l8 | P1 eth5 → Gi0/0/0/4, RR1 eth1 → Gi0/0/0/0 |
| bmp | RR1 eth2 → Gi0/0/0/1, gobmp eth1 |
| l10 | PE1 eth2 → Gi0/0/0/1, CE1 eth1 → Gi0/0/0/0 (dot1q 100/200 inside XR) |
| l11 | PE2 eth3 → Gi0/0/0/2, CE2 eth1 → Gi0/0/0/0 (dot1q 100/200 inside XR) |

Docker can attach networks in an order that doesn't match the eth numbering above. Either pin it with `XR_INTERFACES`, or use `xr-compose` from `xrd-tools`, which builds the per-link networks for you.

### 6.3 Compose skeleton (RR1 and gobmp shown)

```yaml
services:
  rr1:
    image: ios-xr/xrd-control-plane:<version>
    container_name: rr1
    privileged: true            # lab shortcut; use Cisco's capability list for anything shared
    volumes:
      - ./configs/rr1.cfg:/etc/xrd/startup.cfg
      - rr1-data:/xr-storage
    environment:
      XR_EVERY_BOOT_CONFIG: /etc/xrd/startup.cfg
      XR_MGMT_INTERFACES: "linux:eth0,xr_name=Mg0/RP0/CPU0/0,chksum"
      XR_INTERFACES: "linux:eth1,xr_name=Gi0/0/0/0;linux:eth2,xr_name=Gi0/0/0/1"
    networks:
      mgmt: {}
      l8: {}
      bmp: {}

  gobmp:
    image: <gobmp image>        # check the current image name/tag
    container_name: gobmp
    command: ["--source-port=5000", "--dump=console"]   # verify flags for your build; use Kafka for Jalapeno
    networks:
      bmp:
        ipv4_address: 192.168.100.10

networks:
  mgmt: { ipam: { config: [ { subnet: 172.20.0.0/24 } ] } }
  l8:   { internal: true, ipam: { config: [ { subnet: 172.30.8.0/24 } ] } }
  bmp:  { ipam: { config: [ { subnet: 192.168.100.0/24, gateway: 192.168.100.254 } ] } }
  # l1 ... l11: same pattern as l8 with unique dummy subnets

volumes:
  rr1-data:
```

Repeat the `rr1` block for every XRd node using the mapping table in 6.2.

---

## 7. Configurations

Full configs are shown for PE1, P1, ASBR1, RR1, EXT1 and CE1. P2, PE2 and CE2 are listed as deltas.

### 7.1 Common snippets (all IS-IS core nodes)

```
segment-routing
 global-block 16000 23999
 srv6
  encapsulation
   source-address fd00::<N>
  locators
   locator ALGO0
    micro-segment behavior unode psp-usd
    prefix fcbb:bb00:<N>::/48
   !
   locator ALGO128
    micro-segment behavior unode psp-usd
    prefix fcbb:bb01:<N>::/48
    algorithm 128
!
route-policy PASS
  pass
end-policy
```

### 7.2 P1 (L1/L2, BGP-LS producer)

```
hostname P1
interface Loopback0
 ipv4 address 10.0.0.2 255.255.255.255
 ipv6 address fd00::2/128
interface GigabitEthernet0/0/0/0
 description L1-PE1
 ipv4 address 10.1.1.2 255.255.255.252
 ipv6 address fd00:1:1::2/64
interface GigabitEthernet0/0/0/1
 description L2-P2-a
 ipv4 address 10.1.2.1 255.255.255.252
 ipv6 address fd00:1:2::1/64
interface GigabitEthernet0/0/0/2
 description L3-P2-b
 ipv4 address 10.1.3.1 255.255.255.252
 ipv6 address fd00:1:3::1/64
interface GigabitEthernet0/0/0/3
 description L6-LAN
 ipv4 address 10.1.6.2 255.255.255.0
 ipv6 address fd00:1:6::2/64
interface GigabitEthernet0/0/0/4
 description L8-RR1
 ipv4 address 10.1.8.1 255.255.255.252
 ipv6 address fd00:1:8::1/64
!
router isis CORE
 is-type level-1-2
 net 49.0001.0000.0000.0002.00
 distribute link-state instance-id 100
 flex-algo 128
  metric-type delay
  advertise-definition
 !
 address-family ipv4 unicast
  metric-style wide
  segment-routing mpls
 address-family ipv6 unicast
  metric-style wide
  segment-routing srv6
   locator ALGO0
   locator ALGO128
 !
 interface Loopback0
  passive
  address-family ipv4 unicast
   prefix-sid index 2
   prefix-sid algorithm 128 index 102
  address-family ipv6 unicast
 interface GigabitEthernet0/0/0/0
  circuit-type level-1
  point-to-point
  address-family ipv4 unicast
   metric 10
  address-family ipv6 unicast
   metric 10
 interface GigabitEthernet0/0/0/1
  circuit-type level-2-only
  point-to-point
  address-family ipv4 unicast
   metric 10
  address-family ipv6 unicast
   metric 10
 interface GigabitEthernet0/0/0/2
  circuit-type level-2-only
  point-to-point
  address-family ipv4 unicast
   metric 20
  address-family ipv6 unicast
   metric 20
 interface GigabitEthernet0/0/0/3
  circuit-type level-2-only
  ! NO point-to-point: broadcast for pseudonode / LAN End.X
  address-family ipv4 unicast
   metric 10
  address-family ipv6 unicast
   metric 10
 interface GigabitEthernet0/0/0/4
  circuit-type level-2-only
  point-to-point
  address-family ipv4 unicast
   metric 100
  address-family ipv6 unicast
   metric 100
!
! Static delay for Flex-Algo 128 (usec). Values are deliberately unequal.
performance-measurement
 interface GigabitEthernet0/0/0/0
  delay-measurement
   advertise-delay 1000
 interface GigabitEthernet0/0/0/1
  delay-measurement
   advertise-delay 2000
 interface GigabitEthernet0/0/0/2
  delay-measurement
   advertise-delay 500
 interface GigabitEthernet0/0/0/3
  delay-measurement
   advertise-delay 3000
!
router bgp 65000
 bgp router-id 10.0.0.2
 address-family link-state link-state
 neighbor fd00::6
  remote-as 65000
  update-source Loopback0
  address-family link-state link-state
```

**Verify:** the `advertise-delay` static delay syntax and `distribute link-state` options (level, throttle) on your release.

### 7.3 P2 (delta from P1)

- **Loopbacks and NET:** 10.0.0.3, fd00::3, NET 49.0002.0000.0000.0003.00.
- **SIDs:** index 3 and algo-128 index 103. Use the locators for N=3.
- **Interfaces:**
  - Gi0/0/0/0 (L2): .2, metric **15**.
  - Gi0/0/0/1 (L3): .2, metric 20.
  - Gi0/0/0/2 (L4 to PE2): circuit-type level-1, 10.1.4.1.
  - Gi0/0/0/3 (L6): 10.1.6.3, broadcast.
- **Flex-Algo:** keep `advertise-definition`. Both P1 and P2 advertise the FAD.
- **BGP:** same producer config with router-id 10.0.0.3.

### 7.4 ASBR1 (L1/L2 + EPE)

```
hostname ASBR1
interface Loopback0
 ipv4 address 10.0.0.5 255.255.255.255
 ipv6 address fd00::5/128
interface GigabitEthernet0/0/0/0
 description L6-LAN
 ipv4 address 10.1.6.5 255.255.255.0
 ipv6 address fd00:1:6::5/64
interface GigabitEthernet0/0/0/1
 description L5-PE2-flap
 ipv4 address 10.1.5.2 255.255.255.252
 ipv6 address fd00:1:5::2/64
interface GigabitEthernet0/0/0/2
 description L7-EXT1
 ipv4 address 172.16.57.1 255.255.255.252
 ipv6 address fd00:172:57::1/64
!
router isis CORE
 is-type level-1-2
 net 49.0002.0000.0000.0005.00
 flex-algo 128
 address-family ipv4 unicast
  metric-style wide
  segment-routing mpls
 address-family ipv6 unicast
  metric-style wide
  segment-routing srv6
   locator ALGO0
   locator ALGO128
 interface Loopback0
  passive
  address-family ipv4 unicast
   prefix-sid index 5
   prefix-sid algorithm 128 index 105
  address-family ipv6 unicast
 interface GigabitEthernet0/0/0/0
  circuit-type level-2-only
  address-family ipv4 unicast
  address-family ipv6 unicast
 interface GigabitEthernet0/0/0/1
  circuit-type level-1
  point-to-point
  address-family ipv4 unicast
   metric 30
  address-family ipv6 unicast
   metric 30
!
router bgp 65000
 bgp router-id 10.0.0.5
 segment-routing srv6          ! Verify: needed for SRv6 EPE SIDs
  locator ALGO0
 address-family ipv4 unicast
 address-family ipv6 unicast
 address-family link-state link-state
 neighbor fd00::6
  remote-as 65000
  update-source Loopback0
  address-family link-state link-state
 neighbor 172.16.57.2
  remote-as 65001
  egress-engineering
  address-family ipv4 unicast
   route-policy PASS in
   route-policy PASS out
 neighbor fd00:172:57::2
  remote-as 65001
  egress-engineering
  address-family ipv6 unicast
   route-policy PASS in
   route-policy PASS out
```

ASBR1 doesn't run `distribute link-state` under IS-IS. P1 and P2 already cover both areas, so ASBR1 contributes only BGP EPE NLRIs.

### 7.5 PE1 (L1 + VRF OSPF, SAFI 72 producer)

`distribute link-state` sits at the OSPF **process** level (it is rejected in VRF mode). One process per VRF and per protocol keeps a distinct instance-id for each VRF LSDB. Whether a process-level `distribute link-state` exports the LSDB of the VRF configured under that process is checked by F2b/F3b.

```
hostname PE1
vrf CUST-A
 address-family ipv4 unicast
  import route-target 65000:100
  export route-target 65000:100
 address-family ipv6 unicast
  import route-target 65000:100
  export route-target 65000:100
vrf CUST-B
 address-family ipv4 unicast
  import route-target 65000:200
  export route-target 65000:200
 address-family ipv6 unicast
  import route-target 65000:200
  export route-target 65000:200
!
interface Loopback0
 ipv4 address 10.0.0.1 255.255.255.255
 ipv6 address fd00::1/128
interface GigabitEthernet0/0/0/0
 description L1-P1
 ipv4 address 10.1.1.1 255.255.255.252
 ipv6 address fd00:1:1::1/64
interface GigabitEthernet0/0/0/1
 description L10-CE1-trunk
interface GigabitEthernet0/0/0/1.100
 vrf CUST-A
 ipv4 address 192.168.11.1 255.255.255.252
 ipv6 address fd00:11::1/64
 encapsulation dot1q 100
interface GigabitEthernet0/0/0/1.200
 vrf CUST-B
 ipv4 address 192.168.11.1 255.255.255.252
 ipv6 address fd00:11::1/64
 encapsulation dot1q 200
!
router isis CORE
 is-type level-1
 net 49.0001.0000.0000.0001.00
 flex-algo 128
 address-family ipv4 unicast
  metric-style wide
  segment-routing mpls
 address-family ipv6 unicast
  metric-style wide
  segment-routing srv6
   locator ALGO0
   locator ALGO128
 interface Loopback0
  passive
  address-family ipv4 unicast
   prefix-sid index 1
   prefix-sid algorithm 128 index 101
  address-family ipv6 unicast
 interface GigabitEthernet0/0/0/0
  point-to-point
  address-family ipv4 unicast
  address-family ipv6 unicast
!
! ---- OSPFv2: one process per VRF, distribute link-state at process level ----
router ospf VPN-A
 distribute link-state instance-id 200       ! Verify (F2 / F2b)
 vrf CUST-A
  router-id 10.0.1.1
  redistribute bgp 65000
  area 0
   interface GigabitEthernet0/0/0/1.100
    network point-to-point
!
router ospf VPN-B
 distribute link-state instance-id 300       ! Verify (F2 / F2b)
 vrf CUST-B
  router-id 10.0.1.1
  redistribute bgp 65000
  area 0
   interface GigabitEthernet0/0/0/1.200
    network point-to-point
!
! ---- OSPFv3: one process per VRF, distribute link-state at process level ----
router ospfv3 VPN6-A
 distribute link-state instance-id 201       ! Verify (F3 / F3b)
 vrf CUST-A
  router-id 10.0.1.1
  redistribute bgp 65000
  area 0
   interface GigabitEthernet0/0/0/1.100
    network point-to-point
!
router ospfv3 VPN6-B
 distribute link-state instance-id 301       ! Verify (F3 / F3b)
 vrf CUST-B
  router-id 10.0.1.1
  redistribute bgp 65000
  area 0
   interface GigabitEthernet0/0/0/1.200
    network point-to-point
!
router bgp 65000
 bgp router-id 10.0.0.1
 segment-routing srv6
  locator ALGO0
 address-family vpnv4 unicast
 address-family vpnv6 unicast
 address-family link-state vpn               ! Verify exact keyword (F1)
 neighbor fd00::6
  remote-as 65000
  update-source Loopback0
  address-family vpnv4 unicast
  address-family vpnv6 unicast
  address-family link-state vpn
 vrf CUST-A
  rd 10.0.0.1:100
  address-family ipv4 unicast
   segment-routing srv6
    locator ALGO0
    alloc mode per-vrf
   redistribute ospf VPN-A
  address-family ipv6 unicast
   segment-routing srv6
    locator ALGO0
    alloc mode per-vrf
   redistribute ospfv3 VPN6-A
 vrf CUST-B
  rd 10.0.0.1:200
  address-family ipv4 unicast
   segment-routing srv6
    locator ALGO0
    alloc mode per-vrf
   redistribute ospf VPN-B
  address-family ipv6 unicast
   segment-routing srv6
    locator ALGO0
    alloc mode per-vrf
   redistribute ospfv3 VPN6-B
```

- Each VRF address family needs its `segment-routing srv6 locator` line. Without it, BGP silently advertises no VPN routes.
- Optional tuning per process: `distribute link-state instance-id <id> throttle <ms> follow-on <ms>`.
- If F2b/F3b fail on your release (process-level export covers only the default VRF), VRF OSPF can't feed BGP-LS on this image regardless of the SAFI 72 result.

### 7.6 PE2 (delta from PE1)

- **Loopbacks and NET:** 10.0.0.4, fd00::4, NET 49.0002.0000.0000.0004.00.
- **SIDs:** index 4 and algo-128 index 104. Use the locators for N=4.
- **Interfaces:**
  - Gi0/0/0/0 (L4): 10.1.4.2.
  - Gi0/0/0/1 (L5 to ASBR1): 10.1.5.1, metric 30, point-to-point.
  - Gi0/0/0/2.100 and .200: 192.168.12.1/30 and fd00:12::1/64.
- **VRF OSPF:** same four processes as PE1 (`VPN-A`, `VPN-B`, `VPN6-A`, `VPN6-B`) with the same process-level instance-ids (200/300/201/301), router-id 10.0.4.1 under each VRF, and interfaces Gi0/0/0/2.100 / Gi0/0/0/2.200.
- **BGP VRF redistribution:** same process names as PE1.
- **RDs:** 10.0.0.4:100 and 10.0.0.4:200.

### 7.7 RR1 (RR + BMP)

```
hostname RR1
interface Loopback0
 ipv4 address 10.0.0.6 255.255.255.255
 ipv6 address fd00::6/128
interface GigabitEthernet0/0/0/0
 description L8-P1
 ipv4 address 10.1.8.2 255.255.255.252
 ipv6 address fd00:1:8::2/64
interface GigabitEthernet0/0/0/1
 description L9-gobmp
 ipv4 address 192.168.100.1 255.255.255.0
 ipv6 address fd00:100::1/64
!
router isis CORE
 is-type level-2-only
 net 49.0001.0000.0000.0006.00
 set-overload-bit
 address-family ipv4 unicast
  metric-style wide
  segment-routing mpls
 address-family ipv6 unicast
  metric-style wide
  segment-routing srv6
   locator ALGO0
 interface Loopback0
  passive
  address-family ipv4 unicast
   prefix-sid index 6
  address-family ipv6 unicast
 interface GigabitEthernet0/0/0/0
  point-to-point
  address-family ipv4 unicast
   metric 100
  address-family ipv6 unicast
   metric 100
!
bmp server 1
 host 192.168.100.10 port 5000
 update-source GigabitEthernet0/0/0/1
 initial-delay 5
 stats-reporting-period 60
!
router bgp 65000
 bgp router-id 10.0.0.6
 address-family vpnv4 unicast
 address-family vpnv6 unicast
 address-family link-state link-state
 neighbor-group LS-PRODUCERS                 
  remote-as 65000
  update-source Loopback0
  bmp-activate server 1
  address-family link-state link-state
   route-reflector-client
 neighbor-group PE-CLIENTS                   
  remote-as 65000
  update-source Loopback0
  bmp-activate server 1
  address-family vpnv4 unicast
   route-reflector-client
  address-family vpnv6 unicast
   route-reflector-client
  address-family link-state vpn
   route-reflector-client
 neighbor fd00::2 use neighbor-group LS-PRODUCERS
 neighbor fd00::3 use neighbor-group LS-PRODUCERS
 neighbor fd00::5 use neighbor-group LS-PRODUCERS
 neighbor fd00::1 use neighbor-group PE-CLIENTS
 neighbor fd00::4 use neighbor-group PE-CLIENTS

```

- **Locator:** RR1 needs only the ALGO0 locator. It doesn't participate in Flex-Algo 128.
- **BMP:** `bmp-activate` sends per-peer Adj-RIB-In, so gobmp sees both P1's and P2's copies of the shared L2 NLRIs. If your release supports BMP Loc-RIB (RFC 9069), enable it too. That gives one best-path copy for de-duplication tests.
- **Verify:** the Loc-RIB command on your release.

### 7.8 EXT1 (AS 65001)

```
hostname EXT1
interface Loopback0
 ipv4 address 10.0.0.7 255.255.255.255
 ipv6 address fd00::7/128
interface GigabitEthernet0/0/0/0
 ipv4 address 172.16.57.2 255.255.255.252
 ipv6 address fd00:172:57::2/64
route-policy PASS
  pass
end-policy
router bgp 65001
 bgp router-id 10.0.0.7
 address-family ipv4 unicast
  network 10.0.0.7/32
 address-family ipv6 unicast
  network fd00::7/128
 neighbor 172.16.57.1
  remote-as 65000
  address-family ipv4 unicast
   route-policy PASS in
   route-policy PASS out
 neighbor fd00:172:57::1
  remote-as 65000
  address-family ipv6 unicast
   route-policy PASS in
   route-policy PASS out
```

### 7.9 CE1 (VRF-lite, overlapping VRFs)

CEs don't produce BGP-LS, so no `distribute link-state` is needed here.

```
hostname CE1
vrf A
 address-family ipv4 unicast
 address-family ipv6 unicast
vrf B
 address-family ipv4 unicast
 address-family ipv6 unicast
!
interface Loopback100
 vrf A
 ipv4 address 10.11.0.1 255.255.255.255
 ipv6 address fd00:11:ff::1/128
interface Loopback101
 vrf A
 ipv4 address 10.11.1.1 255.255.255.0      
interface Loopback200
 vrf B
 ipv4 address 10.11.0.1 255.255.255.255     
 ipv6 address fd00:11:ff::1/128
interface Loopback201
 vrf B
 ipv4 address 10.11.1.1 255.255.255.0
interface GigabitEthernet0/0/0/0.100
 vrf A
 ipv4 address 192.168.11.2 255.255.255.252
 ipv6 address fd00:11::2/64
 encapsulation dot1q 100
interface GigabitEthernet0/0/0/0.200
 vrf B
 ipv4 address 192.168.11.2 255.255.255.252
 ipv6 address fd00:11::2/64
 encapsulation dot1q 200
!
router ospf CE
 vrf A
  router-id 10.11.0.1
  area 0
   interface Loopback100
    passive
   interface Loopback101
    passive
   interface GigabitEthernet0/0/0/0.100
    network point-to-point
 vrf B
  router-id 10.11.0.1
  area 0
   interface Loopback200
    passive
   interface Loopback201
    passive
   interface GigabitEthernet0/0/0/0.200
    network point-to-point
!
router ospfv3 CE6
 vrf A
  router-id 10.11.0.1
  area 0
   interface Loopback100
   interface GigabitEthernet0/0/0/0.100
    network point-to-point
 vrf B
  router-id 10.11.0.1
  area 0
   interface Loopback200
   interface GigabitEthernet0/0/0/0.200
    network point-to-point
```

**CE2 delta:** replace 11 with 12 throughout (10.12.0.1, 192.168.12.0/30, fd00:12::, fd00:12:ff::1).

---

## 8. Bring-up order

1. **Phase 0:** PE1, P1 and RR1 only. Run F1 to F3 and decide whether to keep SAFI 72 on XRd.
2. **Phase 1 (IGP):** start all XRd nodes. Check IS-IS adjacencies, the LAN DIS, SR-MPLS and SRv6 locators.
3. **Phase 2 (BGP):** check iBGP to RR1, eBGP to EXT1, and EPE.
4. **Phase 3 (BMP):** start gobmp and check that the BMP session is up (F4).
5. **Phase 4 (VPN):** configure the VRFs, CE OSPF and SAFI 72. Run F2b/F3b.
6. **Phase 5:** run the test cases in section 9.

### Baseline verification

| Area | Command | Expected |
|---|---|---|
| IS-IS | `show isis adjacency` | P1: L1 to PE1, L2 to P2 ×2 + LAN + RR1 |
| LAN | `show isis database detail \| i <DIS>` | Pseudonode LSP present for L6 |
| SRv6 | `show segment-routing srv6 locator` | ALGO0/ALGO128 Up |
| SRv6 SIDs | `show segment-routing srv6 sid` | End, End.X, LAN End.X (on L6 nodes) |
| Flex-Algo | `show isis flex-algo 128` | FAD from P1/P2, delay metric |
| VRF OSPF | `show ospf VPN-A vrf CUST-A neighbor`, `show ospfv3 VPN6-A vrf CUST-A neighbor` (and VPN-B / VPN6-B) on PE1 | FULL to CE1 in each VRF |
| BGP | `show bgp link-state link-state summary` (RR1) | P1, P2, ASBR1 Established, prefixes > 0 |
| VPN | `show bgp vpnv4 unicast summary` (RR1) | PE1, PE2 Established |
| SAFI 72 | `show bgp link-state vpn summary` (RR1) (Verify) | PE1, PE2 Established |
| AF negotiation | `show bgp neighbor fd00::1 \| i Address family` | link-state vpn listed as negotiated |
| BMP | `show bgp bmp server 1` (Verify) | Connected, route monitoring active |
| EPE | `show bgp egress-engineering` (ASBR1) | Peer-Node / Peer-Adj SIDs, MPLS + SRv6 |

---

## 9. Test cases

Record a gobmp output snippet as evidence for each test. Use `--dump=console`, or the Kafka topics if you're feeding Jalapeno.

### 9.1 SAFI 71 base and SR

| ID | Test | Action | Expected at gobmp |
|---|---|---|---|
| T-B01 | Node NLRIs | Baseline | One node NLRI per IS-IS node (PE1, P1, P2, PE2, ASBR1, RR1). Protocol-ID 1 (L1) / 2 (L2) |
| T-B02 | Multi-area | Baseline | Area IDs 49.0001 and 49.0002 in the node attributes |
| T-B03 | Duplicate feeds | Baseline | The same L2 NLRIs arrive via P1 and P2 peers (per-peer). Check how gobmp de-duplicates |
| T-B04 | Parallel links | Baseline | Two separate P1–P2 link NLRIs with distinct link descriptors and Adj-SIDs |
| T-B05 | Asymmetric metric | Baseline | L2 link NLRI P1→P2 has IGP metric 10, P2→P1 has 15 |
| T-B06 | Overload bit | Baseline | RR1 node NLRI carries the overload flag |
| T-B07 | Prefix SIDs | Baseline | Prefix NLRIs with SID index (algo 0 and 128) |
| T-B08 | Flex-Algo | Baseline | FAD TLV (1039) on P1/P2 node NLRIs; delay attribute on links |
| T-B09 | Link flap | Shut L5, wait, then no shut | L5 link NLRIs withdrawn, then re-advertised. Measure the timing |
| T-B10 | Feed loss | Shut L8 | RR1 loses all iBGP sessions. gobmp receives BMP peer-down for every peer. Recovery after no shut |

### 9.2 SRv6 extensions (RFC 9514)

| ID | Test | Action | Expected at gobmp |
|---|---|---|---|
| T-S01 | SRv6 capabilities | Baseline | SRv6 Capabilities TLV on node NLRIs |
| T-S02 | Locators | Baseline | Prefix NLRIs for each /48 locator with the SRv6 Locator TLV, algo 0 and 128 |
| T-S03 | SID NLRI | Baseline | SRv6 SID NLRIs (End / uN) with endpoint behavior and SID structure (32/16/0/80) |
| T-S04 | End.X | Baseline | End.X SID TLV on P2P links, two distinct SIDs for L2 and L3 |
| T-S05 | LAN End.X | Baseline | LAN End.X TLVs on the L6 links via the pseudonode, with neighbor system-IDs |
| T-S06 | Locator withdraw | Remove ALGO128 on PE2 | Only PE2's algo-128 locator and SIDs withdrawn |
| T-S07 | DIS change | Change DIS priority on L6 | Pseudonode re-originated by the new DIS. Old link NLRIs withdrawn, new ones added |

### 9.3 EPE (RFC 9086 / RFC 9514)

| ID | Test | Action | Expected at gobmp |
|---|---|---|---|
| T-E01 | MPLS EPE | Baseline | BGP link NLRI (protocol-ID BGP) ASBR1→EXT1 with Peer-Node and Peer-Adj SIDs |
| T-E02 | SRv6 EPE | Baseline | SRv6 BGP Peer Node SID TLV on the IPv6 session NLRI (if F5 passed) |
| T-E03 | Peer down | Shut L7 | EPE NLRIs for both sessions withdrawn |

### 9.4 SAFI 72 (BGP-LS-VPN)

| ID | Test | Action | Expected at gobmp |
|---|---|---|---|
| T-V01 | SAFI 72 present | Baseline | NLRIs with AFI 16388 / SAFI 72, each prefixed with an RD |
| T-V02 | Protocol IDs | Baseline | OSPFv2 (3) and OSPFv3 (6) NLRIs under the same RD, with instance-ids 200/201 (A, processes VPN-A/VPN6-A) and 300/301 (B, processes VPN-B/VPN6-B) |
| T-V03 | VRF separation | Baseline | CUST-A and CUST-B NLRIs with identical node and prefix descriptors (router-ids 10.0.1.1 / 10.11.0.1, prefix 10.11.1.0/24) appear as **separate** entries, distinguished by RD |
| T-V04 | RT preserved | Baseline | RT 65000:100 or 65000:200 extended community kept on each SAFI 72 update |
| T-V05 | SAFI 71/72 isolation | Baseline | No VRF OSPF data in SAFI 71. No IS-IS data in SAFI 72. PE1 appears in both but in separate topologies |
| T-V06 | Per-VRF withdraw | Shut PE1 Gi0/0/0/1.200 | Only CUST-B (RD 10.0.0.1:200) link and prefix NLRIs for PE1–CE1 withdrawn. CUST-A untouched |
| T-V07 | Prefix withdraw | Shut CE1 Loopback101 (VRF A) | Only the 10.11.1.0/24 prefix NLRI under RD 10.0.0.1:100 withdrawn |
| T-V08 | VRF delete / re-add | Remove VRF CUST-B on PE2, then re-add | Bulk withdraw of RD 10.0.0.4:200, followed by full re-advertisement |
| T-V09 | Same-RD collision (optional) | Set CUST-A RD to 65000:100 on PE1 and PE2 | NLRIs from PE1 and PE2 stay separate, since node descriptors differ. Check for overwrites in gobmp |
| T-V10 | RD change | Change PE1 CUST-A RD to 10.0.0.1:101 | Withdraw under the old RD, advertise under the new RD, no stale entries |
| T-V11 | Instance-id change | Under `router ospf VPN-A` (process level) change `distribute link-state instance-id 200` → `210` | Old NLRIs withdrawn, new ones with identifier 210 |
| T-V12 | Session reset | `clear bgp link-state vpn fd00::1` (Verify) on RR1 | gobmp handles BMP peer-down/up for PE1 and the full re-sync of SAFI 72 only |

### 9.5 Results template

| ID | Date | XRd version | gobmp version | Result (Pass/Fail/Blocked) | Evidence / notes |
|---|---|---|---|---|---|
| F1 | | | | | |
| F2 / F2b | | | | | |
| F3 / F3b | | | | | |
| T-V01 | | | | | |

---

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Session up, 0 LS prefixes | `distribute link-state` missing under IS-IS/OSPF process, or the AF isn't negotiated on both sides |
| `distribute link-state` rejected / only `distribute-list in\|out` offered | Command entered in VRF mode. Enter it at the `router ospf <proc>` / `router ospfv3 <proc>` process level |
| VRF OSPF LSDB missing from BGP-LS, IS-IS present | Process-level export may cover only the default VRF on this release (F2b/F3b) |
| CUST-A and CUST-B share one identifier | Both VRFs under one OSPF process. A process takes a single instance-id; use one process per VRF |
| VPNv4 routes missing | Missing `segment-routing srv6 locator` under the VRF AF |
| No pseudonode / LAN End.X | `point-to-point` was set on the L6 interfaces |
| Flex-Algo 128 not computed | No FAD advertised, or no delay values on links |
| gobmp sees peers but no LS NLRIs | BMP not exporting link-state AFs on this release (F4), or `bmp-activate` missing on that neighbor-group |
| Only one copy of the shared L2 NLRIs | Expected only with Loc-RIB monitoring. With Adj-RIB-In, both P1 and P2 copies should appear |
| XR interface addresses conflict | Docker network subnets overlap lab IPs. Use dummy IPAM subnets |
| Interfaces mapped to the wrong links | Docker attachment order. Pin with `XR_INTERFACES` or use `xr-compose` |
| CUST-A and CUST-B merged in gobmp | Decoder ignoring the RD. This is exactly what T-V03 is designed to catch |
