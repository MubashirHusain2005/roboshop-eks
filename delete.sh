#!/bin/bash
# delete-helm-releases.sh
# Description: Delete all Helm releases in all namespaces

set -e

echo "Listing all Helm releases in all namespaces..."
RELEASES=$(helm list -A -q)

if [ -z "$RELEASES" ]; then
  echo "No Helm releases found. Nothing to delete."
  exit 0
fi

echo "Found releases:"
echo "$RELEASES"

for release in $RELEASES; do
  # Get namespace for the release
  NAMESPACE=$(helm list -A | grep "^$release" | awk '{print $2}')
  echo "Deleting release: $release in namespace: $NAMESPACE"
  helm uninstall "$release" -n "$NAMESPACE"
done

echo "All Helm releases deleted."