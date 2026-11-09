#!/usr/bin/env bash

set -euo pipefail

# Announce or withdraw paired SRv6 L3VPN Prefix-SID test routes through the
# bgpinjector /v1/routes API. Set the End.DT service SIDs from PE2's config.
API_URL="${API_URL:-http://127.0.0.1:8080/v1/routes}"
PE2_DT4_SID="${PE2_DT4_SID:-fcbb:bb00:12:e002::}"
PE2_DT6_SID="${PE2_DT6_SID:-fcbb:bb00:12:e003::}"

# These must describe PE2's actual SID allocation. Defaults match a common
# 32-bit locator block + 16-bit node + 16-bit function layout.
LOCATOR_BLOCK_LENGTH="${LOCATOR_BLOCK_LENGTH:-32}"
LOCATOR_NODE_LENGTH="${LOCATOR_NODE_LENGTH:-16}"
FUNCTION_LENGTH="${FUNCTION_LENGTH:-16}"
ARGUMENT_LENGTH="${ARGUMENT_LENGTH:-0}"

NEXT_HOP="fc00::12"
RT_ASN="1"
RT_LOCAL="1"
VPNV4_RD="65001:901"
VPNV6_RD="65001:902"
VPNV4_PREFIX="198.51.100.101/32"
VPNV6_PREFIX="2001:db8:100::101/128"
IMPLICIT_NULL_LABEL=3

post_route() {
  curl --fail-with-body --silent --show-error \
    -X POST "${API_URL}" \
    -H 'content-type: application/json' \
    --data "$1"
  printf '\n'
}

announce() {
  local vpnv4 vpnv6
  vpnv4="$(jq -n \
    --arg rd "${VPNV4_RD}" \
    --arg prefix "${VPNV4_PREFIX}" \
    --arg next_hop "${NEXT_HOP}" \
    --arg sid "${PE2_DT4_SID}" \
    --argjson label "${IMPLICIT_NULL_LABEL}" \
    --argjson rt_asn "${RT_ASN}" \
    --argjson rt_local "${RT_LOCAL}" \
    --argjson block "${LOCATOR_BLOCK_LENGTH}" \
    --argjson node "${LOCATOR_NODE_LENGTH}" \
    --argjson function "${FUNCTION_LENGTH}" \
    --argjson argument "${ARGUMENT_LENGTH}" \
    '{address_family:"vpnv4", action:"announce",
      nlri:{labels:[{value:$label,exp:0,is_bos:true}],rd:$rd,prefix:$prefix},
      next_hops:[$next_hop], origin:"igp", local_pref:100,
      extended_communities:[{type:"route_target",format:"two_octet_as",asn:$rt_asn,local:$rt_local}],
      prefix_sid:{tlvs:[{type:5,srv6_service:{sub_tlvs:[{type:1,
        sid_information:{sid:$sid,endpoint_behavior:63,sub_sub_tlvs:[{type:1,
          sid_structure:{locator_block_length:$block,locator_node_length:$node,
            function_length:$function,argument_length:$argument,
            transposition_length:0,transposition_offset:0}}]}}]}}]}}')"

  vpnv6="$(jq -n \
    --arg rd "${VPNV6_RD}" \
    --arg prefix "${VPNV6_PREFIX}" \
    --arg next_hop "${NEXT_HOP}" \
    --arg sid "${PE2_DT6_SID}" \
    --argjson label "${IMPLICIT_NULL_LABEL}" \
    --argjson rt_asn "${RT_ASN}" \
    --argjson rt_local "${RT_LOCAL}" \
    --argjson block "${LOCATOR_BLOCK_LENGTH}" \
    --argjson node "${LOCATOR_NODE_LENGTH}" \
    --argjson function "${FUNCTION_LENGTH}" \
    --argjson argument "${ARGUMENT_LENGTH}" \
    '{address_family:"vpnv6", action:"announce",
      nlri:{labels:[{value:$label,exp:0,is_bos:true}],rd:$rd,prefix:$prefix},
      next_hops:[$next_hop], origin:"igp", local_pref:100,
      extended_communities:[{type:"route_target",format:"two_octet_as",asn:$rt_asn,local:$rt_local}],
      prefix_sid:{tlvs:[{type:5,srv6_service:{sub_tlvs:[{type:1,
        sid_information:{sid:$sid,endpoint_behavior:62,sub_sub_tlvs:[{type:1,
          sid_structure:{locator_block_length:$block,locator_node_length:$node,
            function_length:$function,argument_length:$argument,
            transposition_length:0,transposition_offset:0}}]}}]}}]}}')"

  echo "Announcing VPNv4 ${VPNV4_PREFIX} via ${NEXT_HOP} with PE2 End.DT4 SID ${PE2_DT4_SID}"
  post_route "${vpnv4}"
  echo "Announcing VPNv6 ${VPNV6_PREFIX} via ${NEXT_HOP} with PE2 End.DT6 SID ${PE2_DT6_SID}"
  post_route "${vpnv6}"
}

withdraw() {
  local vpnv4 vpnv6
  vpnv4="$(jq -n \
    --arg rd "${VPNV4_RD}" --arg prefix "${VPNV4_PREFIX}" \
    --argjson label "${IMPLICIT_NULL_LABEL}" \
    '{address_family:"vpnv4",action:"withdraw",
      nlri:{labels:[{value:$label,exp:0,is_bos:true}],rd:$rd,prefix:$prefix}}')"
  vpnv6="$(jq -n \
    --arg rd "${VPNV6_RD}" --arg prefix "${VPNV6_PREFIX}" \
    --argjson label "${IMPLICIT_NULL_LABEL}" \
    '{address_family:"vpnv6",action:"withdraw",
      nlri:{labels:[{value:$label,exp:0,is_bos:true}],rd:$rd,prefix:$prefix}}')"

  echo "Withdrawing VPNv4 ${VPNV4_PREFIX}"
  post_route "${vpnv4}"
  echo "Withdrawing VPNv6 ${VPNV6_PREFIX}"
  post_route "${vpnv6}"
}

case "${1:-}" in
  announce) announce ;;
  withdraw) withdraw ;;
  *)
    echo "Usage: PE2_DT4_SID=<IPv6-SID> PE2_DT6_SID=<IPv6-SID> $0 announce|withdraw" >&2
    exit 2
    ;;
esac
