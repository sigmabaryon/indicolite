#!/usr/bin/env bash
# Usage: ./build.sh [<working-dir>]

working_dir=$1
base_dir="$(dirname "$(realpath -s "$0")")"
start_time=$(date +%s)

# TODO: Check how ostree-pull-local can be useful
[[ -z $working_dir ]] && working_dir="$base_dir/build"

ostree_cache_dir="$working_dir/cache"
ostree_repo_dir="$working_dir/repo"
lockfile="$base_dir/overrides.yaml"
treefile="$base_dir/fedora-indicolite.yaml"

function cleanup() {
  echo "- cleaning up -"
  rm -rf  /var/tmp/rpm-ostree.*
  chown -R "$SUDO_USER":"$SUDO_USER" "$working_dir"
}

function ost() {
  command=$1
  shift
  options=$*

  if [[ -z $ostree_repo_dir ]]; then
    die "incorrect \$ostree_repo_dir"
  fi

  ostree "$command" --repo="$ostree_repo_dir" "$options"
}

function die() {
  echo -e "\033[1;31mError: $*\033[0m"
  cleanup
  exit 255
}

if ! [[ $(id -u) = 0 ]]; then
  die "Permission denied"
fi

mkdir -p "$ostree_cache_dir"
mkdir -p "$ostree_repo_dir"
chown -R root:root "$working_dir"

if [[ ! $(command -v "rpm-ostree") ]]; then
  die "rpm-ostree not installed"
fi

if [[ ! -f $treefile ]]; then
  die "treefile:$treefile does not exist"
fi

if [ ! "$(ls -A "$ostree_repo_dir")" ]; then
  echo "- init ostree repo -"
  ost init --mode=archive
fi

echo "- building tree -"
# shellcheck disable=SC2046
rpm-ostree compose tree \
  --unified-core \
  --cachedir="$ostree_cache_dir" \
  --repo="$ostree_repo_dir" \
  --add-metadata-string="Build=$(date +%d%m%y)" \
  $([[ -s $lockfile ]] && echo "--ex-lockfile=$lockfile") "$treefile" \
  || build_failed="true"

# [[ rpm!= 0 ]] && build_failed="true"

[[ $build_failed == "true" ]] && die "failed to build tree"

cleanup

ost summary -u

echo "- prune older refs -"
ostree --repo="$ostree_repo_dir" prune --refs-only --keep-younger-than="30 days ago"

end_time=$(( $(date +%s) - start_time ))
echo "- success (took $end_time) -"

