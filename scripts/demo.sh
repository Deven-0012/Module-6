#!/usr/bin/env bash
# Runs the assignment scenarios against the deployed cluster and prints evidence.
#
#   ./scripts/demo.sh            # all steps in order
#   ./scripts/demo.sh 2a         # a single step
#
# Steps: 1a 1b (deploy / discovery / both replicas)  2a 2b 2c (readiness)  3a 3b (pod replacement)
set -uo pipefail
cd "$(dirname "$0")/.."

B=$'\e[1;36m'; Y=$'\e[1;33m'; R=$'\e[0m'
banner() { echo; echo "${Y}==================== $* ====================${R}"; }
run()    { echo "${B}\$ $*${R}"; eval "$@"; echo; }
pods()   { kubectl get pods -l app=inventory -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort; }
count()  { echo "${B}# requests per Pod in the last $1${R}";
           kubectl logs deploy/inventory-client --since="$1" | grep -o 'served by [^ ]*' | sort | uniq -c; echo; }
EPS="kubectl get endpointslices -l kubernetes.io/service-name=inventory-service -o custom-columns=NAME:.metadata.name,ADDRESSES:.endpoints[*].addresses[0],READY:.endpoints[*].conditions.ready,PODS:.endpoints[*].targetRef.name"

step_1a() {
  banner "1a. Deployment: 2 Inventory replicas + Service + client"
  run kubectl get deploy,pods,svc -o wide
  run "$EPS"
  run "kubectl exec deploy/inventory-client -- python -c \"import socket; print('inventory-service resolves to', socket.gethostbyname('inventory-service'))\""
}

step_1b() {
  banner "1b. Client calls http://inventory-service:8080 -> both replicas answer"
  run "kubectl logs deploy/inventory-client --tail=12"
  count 30s
}

step_2a() {
  banner "2a. Make one Pod FAIL readiness"
  local target; target=$(pods | head -1)
  echo "$target" > /tmp/module6-unready-pod
  run kubectl exec "$target" -- touch /tmp/not-ready
  sleep 6
  run kubectl get pods -l app=inventory -o wide
  run "$EPS"
  run "kubectl get events --field-selector involvedObject.name=$target,reason=Unhealthy -o custom-columns=LAST:.lastTimestamp,REASON:.reason,MESSAGE:.message | tail -3"
}

step_2b() {
  banner "2b. While unready: Pod still Running, but gets NO traffic"
  local target; target=$(cat /tmp/module6-unready-pod)
  echo "${B}# unready pod: $target${R}"
  sleep 8
  run "kubectl get pod $target -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount"
  run "kubectl logs deploy/inventory-client --since=10s"
  count 10s
}

step_2c() {
  banner "2c. Restore readiness -> Pod receives traffic again"
  local target; target=$(cat /tmp/module6-unready-pod)
  run kubectl exec "$target" -- rm /tmp/not-ready
  sleep 12
  run kubectl get pods -l app=inventory -o wide
  run "$EPS"
  run "kubectl logs deploy/inventory-client --since=8s"
  count 8s
}

step_3a() {
  banner "3a. Delete one Inventory Pod -> Deployment replaces it"
  local victim; victim=$(pods | head -1)
  echo "$victim" > /tmp/module6-deleted-pod
  run kubectl get pods -l app=inventory -o wide
  run kubectl get svc inventory-service
  run kubectl delete pod "$victim" --wait=false
  sleep 1
  run kubectl get pods -l app=inventory -o wide
  run kubectl wait --for=delete pod/"$victim" --timeout=60s
  run kubectl wait --for=condition=Ready pod -l app=inventory --timeout=60s
  run kubectl get pods -l app=inventory -o wide
  run kubectl get svc inventory-service
  run "$EPS"
}

step_3b() {
  banner "3b. Client keeps working through the Service during replacement"
  echo "${B}# deleted pod: $(cat /tmp/module6-deleted-pod)${R}"
  sleep 8
  run "kubectl logs deploy/inventory-client --since=30s"
  count 6s
}

if [[ $# -gt 0 ]]; then
  for s in "$@"; do "step_$s"; done
else
  for s in 1a 1b 2a 2b 2c 3a 3b; do "step_$s"; done
fi
