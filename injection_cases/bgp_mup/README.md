# BGP-MUP API fixtures

These files are request bodies for `POST /v1/routes`.

Example:

```sh
curl -sS -X POST http://127.0.0.1:8080/v1/routes \
  -H 'content-type: application/json' \
  --data-binary @testdata/bgp_mup/ipv4_isd_announce.json
```

The fixture set contains announce/withdraw pairs for every route type in both
`ipv4/bgp-mup` and `ipv6/bgp-mup`, plus additional DSD pairs for the alternate
SRv6 endpoint behaviors. The fixtures intentionally cover the complete set of
MUP Extended Community sub-types, all three defined ST2 TLVs, both ST1 source
address modes, all three Route Target wire formats, and the mandatory MUP
Prefix-SID behaviors.

Coverage summary:

| Area | Covered values |
| --- | --- |
| Route types | ISD, DSD, ST1, ST2 |
| AFI | IPv4 and IPv6 |
| MUP Extended Community | Direct 2-octet AS (`0x00`), Direct IPv4 (`0x01`), Direct 4-octet AS (`0x02`), Interwork 2-octet AS (`0x03`), Interwork IPv4 (`0x04`), Interwork 4-octet AS (`0x05`) |
| Prefix-SID endpoint behavior | GTP4.E, GTP6.E, End.DT4, End.DX4, End.DT6, End.DX6 |
| ST2 TLVs | Session Parameters (1), Interwork Endpoint (2), Source Address (3), with IPv4 and IPv6 values |
| ST1 fields | Source address absent and present |
| MUP MP_REACH next hop | IPv6 for ISD/DSD, IPv4 and IPv6 variants for ST routes |
| Generic path attributes | MED, Local Preference, standard community, large community, and Route Target variants |

The two extra DSD pairs use a distinct RD/address so both End.DT4/DT6 and
End.DX4/DX6 can be advertised without replacing one another in GoBGP's RIB.

The IPv6 ST1 and ST2 announcements intentionally use the IPv4 next hop shown
in the GoBGP MUP examples. The API request conversion and BGP UPDATE encoding
are covered by `pkg/api/bgp_mup_fixture_test.go`.

## Three-container test bed

Start GoBMP, GoBGP, and bgpinjector from the repository root:

```sh
docker compose -f testdata/bgp_mup/docker-compose.yml up -d
```

The bgpinjector API is published on port `18080` by default. Check readiness:

```sh
curl -sS http://127.0.0.1:18080/readyz
```

Post a fixture:

```sh
curl -sS -X POST http://127.0.0.1:18080/v1/routes \
  -H 'content-type: application/json' \
  --data-binary @testdata/bgp_mup/ipv4_isd_announce.json
```

Inspect the GoBGP session and MUP RIBs:

```sh
docker compose -f testdata/bgp_mup/docker-compose.yml exec gobgp gobgp neighbor
docker compose -f testdata/bgp_mup/docker-compose.yml exec gobgp gobgp global rib -a ipv4-mup -j
docker compose -f testdata/bgp_mup/docker-compose.yml exec gobgp gobgp global rib -a ipv6-mup -j
```

GoBGP sends accepted (post-policy) routes to GoBMP over BMP. GoBMP writes
decoded messages as JSON Lines to `testdata/bgp_mup/output/gobmp.jsonl`:

```sh
tail -f testdata/bgp_mup/output/gobmp.jsonl
```

The GoBMP container is configured with verbose logging (`--v=9`) and listens
for BMP on port `5000` inside the compose network. Its BMP port does not need
to be published on the host.

Stop the test bed with:

```sh
docker compose -f testdata/bgp_mup/docker-compose.yml down
```
