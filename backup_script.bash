#!/bin/bash

# Load environment variables
source .env
export BORG_PASSPHRASE="${BORG_PASSPHRASE}"
export BORG_REPO="${BORG_REPO_BASE}"

# Read file paths into an array
readarray -t FILES_OR_DIRS < paths

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

# Loop over files or directories
for item in "${FILES_OR_DIRS[@]}"; do
    export BORG_REPO="${BORG_REPO_BASE}"

    info "Starting backup for $item"

    borg create                         \
        --verbose                       \
        --progress                      \
        --filter AME                    \
        --list                          \
        --stats                         \
        --show-rc                       \
        --compression lz4               \
                                        \
    ::{hostname}-$(basename $item)-$(date +%Y-%m-%d-%H-%M-%S) \
    $item

    backup_exit=$?

    info "Pruning repository"

    # Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
    # archives of THIS machine. The '{hostname}-*' matching is very important to
    # limit prune's operation to this machine's archives and not apply to
    # other machines' archives also:

    borg prune                          \
        --list                          \
        --glob-archives "{hostname}-$(basename $item)*"  \
        --show-rc                       \
        --keep-daily    7               \
        --keep-weekly   4               \
        --keep-monthly  6

    prune_exit=$?

    # actually free repo disk space by compacting segments
    info "Compacting repository"

    borg compact

    compact_exit=$?

    # use highest exit code as global exit code
    global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
    global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

    if [ ${global_exit} -eq 0 ]; then
        info "Backup, Prune, and Compact finished successfully"
    elif [ ${global_exit} -eq 1 ]; then
        info "Backup, Prune, and/or Compact finished with warnings"
    else
        info "Backup, Prune, and/or Compact finished with errors"
    fi

done

exit ${global_exit}
