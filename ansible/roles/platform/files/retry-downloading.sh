#!/usr/bin/env bash
set -uo pipefail
namespace=$1
shift
attempts=${RETRY_ATTEMPTS:-12}

downloading() {
  jq -rn --slurpfile pods <(kubectl get pods -n "$namespace" -o json) \
    --slurpfile events <(kubectl get events -n "$namespace" -o json) '
    ($events[0].items | map(select(.involvedObject.kind == "Pod"))
      | group_by(.involvedObject.name)
      | map({key: .[0].involvedObject.name,
             value: max_by(.lastTimestamp // .eventTime // .firstTimestamp // "")})
      | from_entries) as $last
    | [$pods[0].items[] | select(.status.phase == "Pending" or .status.phase == "Running")
        | .metadata.name as $pod
        | (.status.initContainerStatuses // []) as $init
        | (if $last[$pod].reason == "Pulling" then "\($pod): \($last[$pod].message)" else empty end),
          (($init + (.status.containerStatuses // []))[]
            | select(.state.waiting.reason == "ErrImagePull" or .state.waiting.reason == "ImagePullBackOff")
            | select(.state.waiting.message // "" | test("not found|manifest unknown|unauthorized|denied|40[134]"; "i") | not)
            | "\($pod): повтор скачивания \(.image)"),
          ($init[] | select(.state.running and (.name | startswith("download-")))
            | "\($pod): \(.name)")]
    | first // empty' | grep .
}

for attempt in $(seq "$attempts"); do
  "$@" && exit 0
  status=$?
  [ "$attempt" -lt "$attempts" ] || break
  reason=$(downloading) || exit "$status"
  echo "Загрузка ещё идёт ($reason): повтор $((attempt + 1))/$attempts" >&2
done
exit "$status"
