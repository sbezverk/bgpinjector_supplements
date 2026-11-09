# VPNv4 and VPNv6 Test Route Injection

[`inject_vpn_test_routes.sh`](./inject_vpn_test_routes.sh) sends four VPN route
advertisements or their four matching withdrawals to `bgpinjector`:

| Family | Prefix | Next hop | VPN label | Default RD | Default route target |
| --- | --- | --- | ---: | --- | --- |
| VPNv4 | `1.1.1.1/32` | `10.1.1.1` | `524286` | `10.169.21.121:30` | `65137:30` |
| VPNv4 | `1.1.1.1/32` | `10.1.2.1` | `524287` | `10.169.21.121:30` | `65137:30` |
| VPNv6 | `2001::1:1:1:1/128` | `::ffff:10.1.1.1` | `524286` | `10.169.21.121:30` | `65137:30` |
| VPNv6 | `2001::1:1:1:1/128` | `::ffff:10.1.2.1` | `524287` | `10.169.21.121:30` | `65137:30` |

The RD is taken from the IOS XR `router bgp 65137` configuration for VRF
`NMNET`. The BGP session address `5.5.5.5` is transport information and does not
replace the VPN next hops carried in MP_REACH_NLRI.

NMNET imports and exports route target `65137:30` under both its IPv4 and IPv6
address families. Every advertisement therefore carries `65137:30` by default.

## Prerequisites

- `bgpinjector` is running and its BGP session is established.
- VPNv4 and VPNv6 have been negotiated with the BGP peer.
- The injector is using `-next-hop-mode preserve` so it does not replace the
  next hops in the requests.
- `curl` is installed.

## Usage

Send all four advertisements:

```bash
./scripts/inject_vpn_test_routes.sh advertise
```

Send all four matching withdrawals:

```bash
./scripts/inject_vpn_test_routes.sh withdraw
```

Advertise all routes and then immediately withdraw them:

```bash
./scripts/inject_vpn_test_routes.sh all
```

The withdrawal requests use the same prefix, RD, and label as their matching
advertisements. Therefore, use the same override values for both commands.

## Override parameters

All configurable parameters are environment variables. Values supplied before
the command override the defaults without modifying the script.

| Variable | Default | Description |
| --- | --- | --- |
| `API_URL` | `http://127.0.0.1:8080/v1/routes` | Complete `bgpinjector` route API URL. |
| `VPNV4_RT_ASN` | `65137` | ASN portion of the NMNET VPNv4 import/export route target. |
| `VPNV4_RT_LOCAL` | `30` | Local-administrator portion of the NMNET VPNv4 import/export route target. |
| `VPNV6_RT_ASN` | `65137` | ASN portion of the NMNET VPNv6 import/export route target. |
| `VPNV6_RT_LOCAL` | `30` | Local-administrator portion of the NMNET VPNv6 import/export route target. |
| `NMNET_RD` | `10.169.21.121:30` | RD used by all NMNET VPNv4 and VPNv6 NLRIs. |

The route-target variables use the two-octet-AS format. `VPNV4_RT_ASN` and
`VPNV6_RT_ASN` must therefore be valid 16-bit AS numbers.

## Override examples

Use a remote injector and replace every RD and route target:

```bash
API_URL=http://192.0.2.50:8080/v1/routes \
VPNV4_RT_ASN=64512 \
VPNV4_RT_LOCAL=500 \
VPNV6_RT_ASN=64512 \
VPNV6_RT_LOCAL=600 \
NMNET_RD=10.169.21.121:30 \
./scripts/inject_vpn_test_routes.sh advertise
```

Withdraw the same routes by repeating the same overrides:

```bash
API_URL=http://192.0.2.50:8080/v1/routes \
VPNV4_RT_ASN=64512 \
VPNV4_RT_LOCAL=500 \
VPNV6_RT_ASN=64512 \
VPNV6_RT_LOCAL=600 \
NMNET_RD=10.169.21.121:30 \
./scripts/inject_vpn_test_routes.sh withdraw
```

Only RD values affect withdrawal matching. Route targets appear only in the
advertisements, but keeping the entire override set identical reduces the risk
of withdrawing different NLRIs than the ones advertised.

To avoid repeating a long list of overrides, export them once:

```bash
export API_URL=http://192.0.2.50:8080/v1/routes
export VPNV4_RT_ASN=64512
export VPNV4_RT_LOCAL=500
export VPNV6_RT_ASN=64512
export VPNV6_RT_LOCAL=600
export NMNET_RD=10.169.21.121:30

./scripts/inject_vpn_test_routes.sh advertise
# Inspect the routes in the testbed.
./scripts/inject_vpn_test_routes.sh withdraw
```
