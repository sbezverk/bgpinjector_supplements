#!/usr/bin/env bash

set -euo pipefail

# Update these values for the testbed.
API_URL="${API_URL:-http://127.0.0.1:8080/v1/routes}"

# NMNET imports and exports route target 65137:30 for both address families.
VPNV4_RT_ASN="${VPNV4_RT_ASN:-65137}"
VPNV4_RT_LOCAL="${VPNV4_RT_LOCAL:-30}"

VPNV6_RT_ASN="${VPNV6_RT_ASN:-65137}"
VPNV6_RT_LOCAL="${VPNV6_RT_LOCAL:-30}"

# NMNET uses the same configured RD for its VPNv4 and VPNv6 routes.
NMNET_RD="${NMNET_RD:-10.169.21.121:30}"

post_route() {
  curl --fail-with-body --silent --show-error \
    -X POST "${API_URL}" \
    -H 'content-type: application/json' \
    --data "$1"
  printf '\n'
}

advertise() {
  echo "Advertising VPNv4 1.1.1.1/32 via 10.1.1.1, label 524286"
  post_route "$(
    printf '{
      "address_family": "vpnv4",
      "action": "announce",
      "nlri": {
        "labels": [{"value": 524286, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "1.1.1.1/32"
      },
      "next_hops": ["10.1.1.1"],
      "origin": "igp",
      "extended_communities": [{
        "type": "route_target",
        "format": "two_octet_as",
        "asn": %s,
        "local": %s
      }]
    }' "${NMNET_RD}" "${VPNV4_RT_ASN}" "${VPNV4_RT_LOCAL}"
  )"

  echo "Advertising VPNv6 2001::1:1:1:1/128 via ::ffff:10.1.1.1, label 524286"
  post_route "$(
    printf '{
      "address_family": "vpnv6",
      "action": "announce",
      "nlri": {
        "labels": [{"value": 524286, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "2001::1:1:1:1/128"
      },
      "next_hops": ["::ffff:10.1.1.1"],
      "origin": "igp",
      "extended_communities": [{
        "type": "route_target",
        "format": "two_octet_as",
        "asn": %s,
        "local": %s
      }]
    }' "${NMNET_RD}" "${VPNV6_RT_ASN}" "${VPNV6_RT_LOCAL}"
  )"

  echo "Advertising VPNv4 1.1.1.1/32 via 10.1.2.1, label 524287"
  post_route "$(
    printf '{
      "address_family": "vpnv4",
      "action": "announce",
      "nlri": {
        "labels": [{"value": 524287, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "1.1.1.1/32"
      },
      "next_hops": ["10.1.2.1"],
      "origin": "igp",
      "extended_communities": [{
        "type": "route_target",
        "format": "two_octet_as",
        "asn": %s,
        "local": %s
      }]
    }' "${NMNET_RD}" "${VPNV4_RT_ASN}" "${VPNV4_RT_LOCAL}"
  )"

  echo "Advertising VPNv6 2001::1:1:1:1/128 via ::ffff:10.1.2.1, label 524287"
  post_route "$(
    printf '{
      "address_family": "vpnv6",
      "action": "announce",
      "nlri": {
        "labels": [{"value": 524287, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "2001::1:1:1:1/128"
      },
      "next_hops": ["::ffff:10.1.2.1"],
      "origin": "igp",
      "extended_communities": [{
        "type": "route_target",
        "format": "two_octet_as",
        "asn": %s,
        "local": %s
      }]
    }' "${NMNET_RD}" "${VPNV6_RT_ASN}" "${VPNV6_RT_LOCAL}"
  )"
}

withdraw() {
  echo "Withdrawing VPNv4 1.1.1.1/32, RD ${NMNET_RD}, label 524286"
  post_route "$(
    printf '{
      "address_family": "vpnv4",
      "action": "withdraw",
      "nlri": {
        "labels": [{"value": 524286, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "1.1.1.1/32"
      }
    }' "${NMNET_RD}"
  )"

  echo "Withdrawing VPNv6 2001::1:1:1:1/128, RD ${NMNET_RD}, label 524286"
  post_route "$(
    printf '{
      "address_family": "vpnv6",
      "action": "withdraw",
      "nlri": {
        "labels": [{"value": 524286, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "2001::1:1:1:1/128"
      }
    }' "${NMNET_RD}"
  )"

  echo "Withdrawing VPNv4 1.1.1.1/32, RD ${NMNET_RD}, label 524287"
  post_route "$(
    printf '{
      "address_family": "vpnv4",
      "action": "withdraw",
      "nlri": {
        "labels": [{"value": 524287, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "1.1.1.1/32"
      }
    }' "${NMNET_RD}"
  )"

  echo "Withdrawing VPNv6 2001::1:1:1:1/128, RD ${NMNET_RD}, label 524287"
  post_route "$(
    printf '{
      "address_family": "vpnv6",
      "action": "withdraw",
      "nlri": {
        "labels": [{"value": 524287, "exp": 0, "is_bos": true}],
        "rd": "%s",
        "prefix": "2001::1:1:1:1/128"
      }
    }' "${NMNET_RD}"
  )"
}

usage() {
  echo "Usage: $0 advertise|withdraw|all" >&2
}

case "${1:-}" in
  advertise)
    advertise
    ;;
  withdraw)
    withdraw
    ;;
  all)
    advertise
    withdraw
    ;;
  *)
    usage
    exit 2
    ;;
esac
