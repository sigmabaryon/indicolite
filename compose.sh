#!/usr/bin/env bash
# Usage: ./compose.sh -d [<deploy-dest>] -w [<working-dir>] 

while getopts ":d:w:" opt; do
  case $opt in
    d) deploy_dest="$OPTARG"
    ;;
    w) working_dir="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
  esac

  case $OPTARG in
    -*) echo "Option $opt needs a valid argument"
    exit 1
    ;;
  esac
done

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

function die() {
  echo -e "\033[1;31mError: $*\033[0m"
  cleanup
  exit 255
}

function ost() {
  command=$1
  shift
  options=$*

  if [[ -z $ostree_repo_dir ]]; then
    die "incorrect \$ostree_repo_dir"
  fi

  echo "ostree $command --repo=$ostree_repo_dir $options"
  eval "ostree $command --repo=$ostree_repo_dir $options"
}

function rsnc() {
  local -n _array_incl=$1
  shift
  options=$*
  [[ -z $deploy_dest ]] && \
    {
      echo "- skipping deployment: no deploy-dest specified -"
      return
    }

  rsync_cmd="rsync -rlpt"
  for i in "${_array_incl[@]}"
  do
    rsync_cmd+=" --include=\"$ostree_repo_dir/$i\""
  done
  rsync_cmd+=" --exclude=\"$ostree_repo_dir/*\" $options"
  rsync_cmd+=" $ostree_repo_dir/ $deploy_dest"

  eval "$rsync_cmd"
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
{ 
  rpm-ostree compose tree \
    --unified-core \
    --cachedir="$ostree_cache_dir" \
    --repo="$ostree_repo_dir" \
    --add-metadata-string="Build=$(date +%d%m%y)" \
    $([[ -s $lockfile ]] && echo "--ex-lockfile=$lockfile") "$treefile" \
    || build_failed="true"
    
  [[ $build_failed == "true" ]] && die "failed to build tree"
}

cleanup

ost summary -u

echo "- prune older refs -"
ost prune --refs-only --keep-younger-than="\"30 days ago\""

echo "- deploy -"
# shellcheck disable=SC2034
{
  objs_and_dlts=("objects" "objects/**" "deltas" "deltas/**")
  refs_and_summ=("refs" "refs/**" "summary*" "summaries" "summaries/**")
  config=("config")

  # ref : https://github.com/hyperreal64/vauxite/blob/main/rsync-repos#L55
  rsnc objs_and_dlts --ignore-existing
  rsnc refs_and_summ --delete
  
  rsnc objs_and_dlts --ignore-existing --delete
  rsnc config --ignore-existing
}

end_time=$(( $(date +%s) - start_time ))
echo "- success (took $end_time) -"

