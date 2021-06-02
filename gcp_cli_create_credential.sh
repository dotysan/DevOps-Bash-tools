#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2021-02-20 17:26:21 +0000 (Sat, 20 Feb 2021)
#
#  https://github.com/HariSekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
. "$srcdir/lib/utils.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Creates a GCP service account for GCloud SDK CLI to avoid having to re-login every day with 'gcloud auth login'

Grants this service account 'owner' rights to all projects

Creates and downloads a json credential and even prints the command to activate the credential

export GOOGLE_CREDENTIALS=\$HOME/.gcloud/\$name-\$project-credential.json

The following optional arguments can be given:

- service account name prefix   (default: \$USER-cli)
- credential file path          (default: \$HOME/.gcloud/\$name-\$project-credential.json)
- project                       (default: \$CLOUDSDK_CORE_PROJECT or gcloud config's currently configured project setting core.project)

This can also be used as a backup credential - this way if something accidentally happens to your primary user account
or this service account, you can always use the other to repair access without having to rely on colleagues who be away

Idempotent - safe to re-run, will skip service accounts and keyfiles that already exist
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args="[<name> <credential.json> <project>]"

help_usage "$@"

#min_args 1 "$@"

name="${1:-$USER-cli}"

project="${3:-${CLOUDSDK_CORE_PROJECT:-$(gcloud config list --format='get(core.project)')}}"

# XXX: sets the GCP project for the duration of the script for consistency purposes (relying on gcloud config could lead to race conditions)
not_blank "$project" || die "ERROR: no project specified and \$CLOUDSDK_CORE_PROJECT / GCloud SDK config core.project value not set"
export CLOUDSDK_CORE_PROJECT="$project"

keyfile="${2:-$HOME/.gcloud/$name-$project-credential.json}"

service_account="$name@$project.iam.gserviceaccount.com"

if gcloud iam service-accounts list --format='get(email)' | grep -Fxq "$service_account"; then
    timestamp "Service account '$service_account' already exists"
else
    gcloud iam service-accounts create "$name" --description="$USER's service account for CLI usage" --project "$project"
fi

mkdir -pv "$(dirname "$keyfile")"

if [ -f "$keyfile" ]; then
    timestamp "Credentials keyfile '$keyfile' already exists"
else
    gcloud iam service-accounts keys create "$keyfile" --iam-account="$service_account" --key-file-type="json" --project "$project"
fi

timestamp "Granting Owner permissions to service account '$service_account' on all projects"

for project in $(gcloud projects list --format='get(project_id)'); do
    timestamp "Granting Owner permissions to service account '$service_account' on project '$project'"
    # some projects may require --condition=None in non-interactive mode
    gcloud projects add-iam-policy-binding "$project" --member="serviceAccount:$service_account" --role='roles/owner' --condition=None >/dev/null
done

if is_mac; then
    readlink(){
        command greadlink "$@"
    }
fi

keyfile="$(readlink -e "$keyfile")"

echo
echo "Set this in your environment to use this long-term credential in your CLI:"
echo
echo "export GOOGLE_CREDENTIALS=$keyfile"
echo
