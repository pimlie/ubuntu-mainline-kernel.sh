#!/usr/bin/env bash

# shellcheck disable=SC1117

# Ubuntu Kernel PPA info
ppa_host="kernel.ubuntu.com"
ppa_index="/~kernel-ppa/mainline/"
ppa_key="17C622B0"

# If quiet=1 then no log messages are printed (except errors)
quiet=0

# If check_signature=0 then the signature of the CHECKSUMS file will not be checked
check_signature=1

# If check_checksum=0 then the checksums of the .deb files will not be checked
check_checksum=1

# If doublecheckversion=1 then also check the version specific ppa page to make
# sure the kernel build was successful
doublecheckversion=1

# Connect over http or https to ppa (only https works)
use_https=1

# Path to sudo command, empty by default
sudo=""
#sudo=$(command -v sudo) # Uncomment this line if you dont want to sudo yourself

# Path to wget command
wget=$(command -v wget)

#####
## Below are internal variables of which most can be toggled by command options
## DON'T CHANGE THESE MANUALLY
#####

# (internal) If cleanup_files=1 then before exiting all downloaded/temporaryfiles
# are removed
cleanup_files=1

# (internal) If do_install=0 downloaded deb files will not be installed
do_install=1

# (internal) If use_lowlatency=1 then the lowlatency kernel will be installed
use_lowlatency=0

# (internal) If use_lpae=1 then the lpae kernel will be installed
use_lpae=0

# (internal) If use_snapdragon=1 then the snapdragon kernel will be installed
use_snapdragon=0

# (internal) If use_rc=1 then release candidate kernel versions are also checked
use_rc=0

# (internal) If assume_yes=1 assume yes on all prompts
assume_yes=0

# (internal) How many files we expect to retrieve from the ppa
# checksum, signature, header-all, header-arch, image(-unsigned), modules
expected_files_count=6

# (internal) Which action/command the script should run
run_action="help"

# (internal) The workdir where eg the .deb files are downloaded
workdir="/tmp/$(basename "$0")/"

# (internal) The stdio where all detail output should be sent
debug_target="/dev/null"

# (internal) Holds all version numbers of locally installed ppa kernels
LOCAL_VERSIONS=()

# (internal) Holds all version numbers of available ppa kernels
REMOTE_VERSIONS=()

# (internal) The architecture of the local system
arch=$(dpkg --print-architecture)

# (internal) The text to search for to check if the build was successfully
# NOTE: New succeed text since v5.6.18
build_succeeded_text="(Build for ${arch} succeeded|Test ${arch}/build succeeded)"

# (internal) The pid of the child process which checks download progress
monitor_pid=0

# (internal) The size of the file which is being downloaded
download_size=0

action_data=()

#####
## Check if we are running on an Ubuntu-like OS
#####

# shellcheck disable=SC1091,SC2015
[ -f "/etc/os-release" ] && {
    source /etc/os-release
    [[ "$ID" == "ubuntu" ]] || [[ "$ID_LIKE" =~ "ubuntu" ]]
} || {
    OS=$(lsb_release -si 2>&-)
    [[ "$OS" == "Ubuntu" ]] || [[ "$OS" == "LinuxMint" ]]  || [[ "$OS" == "neon" ]] || {
        echo "Abort, this script is only intended for Ubuntu-like distros"
        exit 2
    }
}

#####
## helper functions
#####

single_action () {
    [ "$run_action" != "help" ] && {
        err "Abort, only one argument can be supplied. See -h"
        exit 2
    }
}

log () {
    [ $quiet -eq 0 ] && echo "$@"
}

logn () {
    [ $quiet -eq 0 ] && echo -n "$@"
}

warn () {
    [ $quiet -eq 0 ] && echo "$@" >&2
}

err () {
    echo "$@" >&2
}

#####
## Simple command options parser
#####

while (( "$#" )); do
    argarg_required=0

    case $1 in
        -c|--check)
            single_action
            run_action="check"
            ;;
        -l|--local-list)
            single_action
            run_action="local-list"
            argarg_required=1
            ;;
        -r|--remote-list)
            single_action
            run_action="remote-list"
            argarg_required=1
            ;;
        -i|--install)
            single_action
            run_action="install"
            argarg_required=1
            ;;
        -u|--uninstall)
            single_action
            run_action="uninstall"
            argarg_required=1
            ;;
        -p|--path)
            if [ -z "$2" ] || [ "${2##-}" != "$2" ]; then
                err "Option $1 requires an argument."
                exit 2
            else
                workdir="$(realpath "$2")/"
                shift

                if [ ! -d "$workdir" ]; then
                    mkdir -p "$workdir";
                fi

                if [ ! -d "$workdir" ] || [ ! -w "$workdir" ]; then
                    err "$workdir is not writable"
                    exit 1
                fi

                cleanup_files=0
            fi
            ;;
        -ll|--lowlatency|--low-latency)
            [[ "$arch" != "amd64" ]] && [[ "$arch" != "i386" ]] && {
                err "Low-latency kernels are only available for amd64 or i386 architectures"
                exit 3
            }

            use_lowlatency=1
            ;;
        -lpae|--lpae)
            [[ "$arch" != "armhf" ]] && {
                err "Large Physical Address Extension (LPAE) kernels are only available for the armhf architecture"
                exit 3
            }

            use_lpae=1
            ;;
        --snapdragon)
            [[ "$arch" != "arm64" ]] && {
                err "Snapdragon kernels are only available for the arm64 architecture"
                exit 3
            }

            use_snapdragon=1
            ;;
        --rc)
            use_rc=1
            ;;
        -s|--signed)
            log "The option '--signed' is not yet implemented"
            ;;
        --yes)
            assume_yes=1
            ;;
        -q|--quiet)
            [ "$debug_target" == "/dev/null" ] && { quiet=1; }
            ;;
        -do|--download-only)
            do_install=0
            cleanup_files=0
            ;;
        -ns|--no-signature)
            check_signature=0
            ;;
        -nc|--no-checksum)
            check_checksum=0
            ;;
        -d|--debug)
            debug_target="/dev/stderr"
            quiet=0
            ;;
        -h|--help)
            run_action="help"
            ;;
        *)
            run_action="help"
            err "Unknown argument $1"
            ;;
    esac

    if [ $argarg_required -eq 1 ]; then
        [ -n "$2" ] && [ "${2##-}" == "$2" ] && {
            action_data+=("$2")
            shift
        }
    elif [ $argarg_required -eq 2 ]; then
        # shellcheck disable=SC2015
        [ -n "$2" ] && [ "${2##-}" == "$2" ] && {
            action_data+=("$2")
            shift
        } || {
            err "Option $1 requires an argument"
            exit 2
        }
    fi

    shift
done

#####
## internal functions
#####

containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] || [[ "$e" =~ $1- ]] && return 0; done
  return 1
}

download () {
    host=$1
    uri=$2

    if [ $use_https -eq 1 ]; then
        $wget -q --save-headers --output-document - "https://$host$uri"
    else
        exec 3<>/dev/tcp/"$host"/80
        echo -e "GET $uri HTTP/1.0\r\nHost: $host\r\nConnection: close\r\n\r\n" >&3
        cat <&3
    fi
}

monitor_progress () {
    local msg=$1
    local file=$2

    download_size=-1
    printf "%s: " "$msg"
    (while :; do for c in / - \\ \|; do
        [[ -f "$file" ]] && {
            # shellcheck disable=SC2015
            [[ $download_size -le 0 ]] && {
                download_size=$(($(head -n20 "$file" | grep -aoi -E "Content-Length: [0-9]+" | cut -d" " -f2) + 0))
                printf ' %d%% %s' 0 "$c"
                printf '\b%.0s' {1..5}
            } || {
                filesize=$(( $(du -b "$file" | cut -f1) + 0))
                progress="$((200*filesize/download_size % 2 + 100*filesize/download_size))"

                printf ' %s%% %s' "$progress" "$c"
                length=$((4 + ${#progress}))
                printf '\b%.0s' $(seq 1 $length)
            }
        }
        sleep 1
    done; done) &
    monitor_pid=$!
}

end_monitor_progress () {
    { kill $monitor_pid && wait $monitor_pid; printf '100%%   \n'; } 2>/dev/null
}

remove_http_headers () {
    file="$1"
    nr=0
    while(true); do
        nr=$((nr + 1))
        line=$(head -n$nr "$file" | tail -n 1)

        if [ -z "$(echo "$line" | tr -cd '\r\n')" ]; then
            tail -n +$nr "$file" > "${file}.tmp"
            mv "${file}.tmp" "${file}"
            break
        fi

        [ $nr -gt 100 ] && {
            err "Abort, could not remove http headers from file"
            exit 3
        }
    done
}

load_local_versions() {
    local version
    if [ ${#LOCAL_VERSIONS[@]} -eq 0 ]; then
        IFS=$'\n'
        for pckg in $(dpkg -l linux-image-* | cut -d " " -f 3 | sort -V); do
            # only match kernels from ppa
            if [[ "$pckg" =~ linux-image-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{6} ]]; then
                version="v"$(echo "$pckg" | cut -d"-" -f 3,4)

                LOCAL_VERSIONS+=("$version")
            fi
        done
        unset IFS
    fi
}

latest_local_version() {
    load_local_versions 1

    if [ ${#LOCAL_VERSIONS[@]} -gt 0 ]; then
        local sorted
        mapfile -t sorted < <(echo "${LOCAL_VERSIONS[*]}" | tr ' ' '\n' | sort -t"." -k1V,3)

        lv="${sorted[${#sorted[@]}-1]}"
        echo "${lv/-[0-9][0-9][0-9][0-9][0-9][0-9]rc/-rc}"
    else
        echo "none"
    fi
}

remote_html_cache=""
parse_remote_versions() {
    local line
    while read -r line; do
        if [[ $line =~ DIR.*href=\"(v[[:digit:]]+\.[[:digit:]]+(\.[[:digit:]]+)?)(-(rc[[:digit:]]+))?/\" ]]; then
            line="${BASH_REMATCH[1]}"
            if [[ -z "${BASH_REMATCH[2]}" ]]; then
                line="$line.0"
            fi
            # temporarily substitute rc suffix join character for correct version sort
            if [[ -n "${BASH_REMATCH[3]}" ]]; then
                line="$line~${BASH_REMATCH[4]}"
            fi
            echo "$line"
        fi
    done <<<"$remote_html_cache"
}

load_remote_versions () {
    local line

    [[ -n "$2" ]] && {
      REMOTE_VERSIONS=()
    }

    if [ ${#REMOTE_VERSIONS[@]} -eq 0 ]; then
        if [ -z "$remote_html_cache" ]; then
          [ -z "$1" ] && logn "Downloading index from $ppa_host"
          remote_html_cache=$(download $ppa_host $ppa_index)
          [ -z "$1" ] && log
        fi

        IFS=$'\n'
        while read -r line; do
            # reinstate original rc suffix join character
            if [[ $line =~ ^([^~]+)~([^~]+)$ ]]; then
                [[ $use_rc -eq 0 ]] && continue
                line="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
            fi
            [[ -n "$2" ]] && [[ ! "$line" =~ $2 ]] && continue
            REMOTE_VERSIONS+=("$line")
        done < <(parse_remote_versions | sort -V)
        unset IFS
    fi
}

latest_remote_version () {
    load_remote_versions 1 "$1"
    echo "${REMOTE_VERSIONS[${#REMOTE_VERSIONS[@]}-1]}"
}

check_environment () {
    if [ $use_https -eq 1 ] && [ -z "$wget" ]; then
        err "Abort, wget not found. Please apt install wget"
        exit 3
    fi
}

guard_run_as_root () {
  if [ "$(id -u)" -ne 0 ]; then
    echo "The '$run_action' command requires root privileges"
    exit 2
  fi  
}

# execute requested action
case $run_action in
    help)
        echo "Usage: $0 -c|-l|-r|-u

Download & install the latest kernel available from $ppa_host$ppa_uri

Arguments:
  -c               Check if a newer kernel version is available
  -i [VERSION]     Install kernel VERSION, see -l for list. You don't have to prefix
                   with v. E.g. -i 4.9 is the same as -i v4.9. If version is
                   omitted the latest available version will be installed
  -l [SEARCH]      List locally installed kernel versions. If an argument to this
                   option is supplied it will search for that
  -r [SEARCH]      List available kernel versions. If an argument to this option
                   is supplied it will search for that
  -u [VERSION]     Uninstall the specified kernel version. If version is omitted,
                   a list of max 10 installed kernel versions is displayed
  -h               Show this message

Optional:
  -s, --signed         Only install signed kernel packages (not implemented)
  -p, --path DIR       The working directory, .deb files will be downloaded into
                       this folder. If omitted, the folder /tmp/$(basename "$0")/
                       is used. Path is relative from \$PWD
  -ll, --low-latency   Use the low-latency version of the kernel, only for amd64 & i386
  -lpae, --lpae        Use the Large Physical Address Extension kernel, only for armhf
  --snapdragon         Use the Snapdragon kernel, only for arm64
  -do, --download-only Only download the deb files, do not install them
  -ns, --no-signature  Do not check the gpg signature of the checksums file
  -nc, --no-checksum   Do not check the sha checksums of the .deb files
  -d, --debug          Show debug information, all internal command's echo their output
  --rc                 Also include release candidates
  --yes                Assume yes on all questions (use with caution!)
"
        exit 2
        ;;

    check)
        check_environment

        logn "Finding latest version available on $ppa_host"
        latest_version=$(latest_remote_version)
        log ": $latest_version"

        logn "Finding latest installed version"
        installed_version=$(latest_local_version)
        installed_version=${installed_version%-*}
        log ": $installed_version"

        # Check if build was successful
        if [ $doublecheckversion -gt 0 ]; then
            ppa_uri=$ppa_index${latest_version%\.0}"/"
            ppa_uri=${ppa_uri/\.0-rc/-rc}

            index=$(download $ppa_host "$ppa_uri")
            if [[ ! $index =~ $build_succeeded_text ]]; then
                 log "A newer kernel version ($latest_version) was found but the build was not successful"

                [ -n "$DISPLAY" ] && [ -x "$(command -v notify-send)" ] && notify-send --icon=info -t 12000 \
                    "Kernel $latest_version available" \
                    "A newer kernel version ($latest_version) is\navailable but the build was not successful"
                exit 1
            fi
        fi

        # Check installed minor branch
        latest_minor_text=""
        latest_minor_notify=""
        latest_minor_version=""
        if [ -n "${installed_version}" ] && [ "${installed_version}" != "none" ] && [ "${latest_version%.*}" != "${installed_version%.*}" ]; then
            latest_minor_version=$(latest_remote_version "${installed_version%.*}")

            if [ "$installed_version" != "$latest_minor_version" ]; then
              latest_minor_text=", latest in current branch is ${latest_minor_version}"
              latest_minor_notify="Version ${latest_minor_version} is available in the current ${installed_version%.*} branch\n\n"
            fi
        fi

        if [ "$installed_version" != "$latest_version" ] && [ "$installed_version" = "$(echo -e "$latest_version\n$installed_version" | sort -V | head -n1)" ]; then
            log "A newer kernel version ($latest_version) is available${latest_minor_text}"

            [ -n "$DISPLAY" ] && [ -x "$(command -v notify-send)" ] && notify-send --icon=info -t 12000 \
                "Kernel $latest_version available" \
                "A newer kernel version ($latest_version) is available\n\n${latest_minor_notify}Run '$(basename "$0") -i' to update\nor visit $ppa_host$ppa_uri"
            exit 1
        fi
        ;;
    local-list)
        load_local_versions

        # shellcheck disable=SC2015
        [[ -n "$(command -v column)" ]] && { column="column -x"; } || { column="cat"; }

        (for version in "${LOCAL_VERSIONS[@]}"; do
            if [ -z "${action_data[0]}" ] || [[ "$version" =~ ${action_data[0]} ]]; then
                echo "$version"
            fi
        done) | $column
        ;;
    remote-list)
        check_environment
        load_remote_versions

        # shellcheck disable=SC2015
        [[ -n "$(command -v column)" ]] && { column="column -x"; } || { column="cat"; }

        (for version in "${REMOTE_VERSIONS[@]}"; do
            if [ -z "${action_data[0]}" ] || [[ "$version" =~ ${action_data[0]} ]]; then
                echo "$version"
            fi
        done) | $column
        ;;
    install)
        # only ensure running if the kernel files should be installed
        [ $do_install -eq 1 ] && guard_run_as_root

        check_environment
        load_local_versions

        if [ -z "${action_data[0]}" ]; then
            logn "Finding latest version available on $ppa_host"
            version=$(latest_remote_version)
            log

            if containsElement "$version" "${LOCAL_VERSIONS[@]}"; then
                logn "Latest version is $version but seems its already installed"
            else
                logn "Latest version is: $version"
            fi

            if [ $do_install -gt 0 ] && [ $assume_yes -eq 0 ];then
                logn ", continue? (y/N) "
                [ $quiet -eq 0 ] && read -rsn1 continue
                log

                [ "$continue" != "y" ] && [ "$continue" != "Y" ] && { exit 0; }
            else
                log
            fi
        else
            load_remote_versions

            version=""
            if containsElement "v${action_data[0]#v}" "${REMOTE_VERSIONS[@]}"; then
                version="v"${action_data[0]#v}
            fi

            [[ -z "$version" ]] && {
                err "Version '${action_data[0]}' not found"
                exit 2
            }
            shift

            if [ $do_install -gt 0 ] && containsElement "$version" "${LOCAL_VERSIONS[@]}" && [ $assume_yes -eq 0 ]; then
                logn "It seems version $version is already installed, continue? (y/N) "
                [ $quiet -eq 0 ] && read -rsn1 continue
                log

                [ "$continue" != "y" ] && [ "$continue" != "Y" ] && { exit 0; }
            fi
        fi

        [ ! -d "$workdir" ] && {
            mkdir -p "$workdir" 2>/dev/null
        }
        [ ! -x "$workdir" ] && {
            err "$workdir is not writable"
            exit 1
        }

        cd "$workdir" || exit 1

        [ $check_signature -eq 1 ] && [ -z "$(command -v gpg)" ] && {
            check_signature=0

            warn "Disable signature check, gpg not available"
        }

        IFS=$'\n'

        ppa_uri=$ppa_index${version%\.0}"/"
        ppa_uri=${ppa_uri/\.0-rc/-rc}

        index=$(download $ppa_host "$ppa_uri")

        if [[ ! $index =~ $build_succeeded_text ]]; then
          err "Abort, the ${arch} build has not succeeded"
          exit 1
        fi

        index=${index%%*<table}

        FILES=()

        found_arch=0
        uses_subfolders=0
        section_end="^[[:space:]]*<br>[[:space:]]*$"
        for line in $index; do
            if [[ $line =~ $build_succeeded_text ]]; then
              found_arch=1
              continue
            elif [ $found_arch -eq 0 ]; then
              continue
            elif [[ $line =~ $section_end ]]; then
              break
            fi

            [[ "$line" =~ linux-(image(-(un)?signed)?|headers|modules)-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{6}.*?_(${arch}|all).deb ]] || continue

            [ $use_lowlatency -eq 0 ] && [[ "$line" =~ "-lowlatency" ]] && continue
            [ $use_lowlatency -eq 1 ] && [[ ! "$line" =~ "-lowlatency" ]] && [[ ! "$line" =~ "_all" ]] && continue
            [ $use_lpae -eq 0 ] && [[ "$line" =~ "-lpae" ]] && continue
            [ $use_lpae -eq 1 ] && [[ ! "$line" =~ "-lpae" ]] && [[ ! "$line" =~ "_all" ]] && continue
            [ $use_snapdragon -eq 0 ] && [[ "$line" =~ "-snapdragon" ]] && continue
            [ $use_snapdragon -eq 1 ] && [[ ! "$line" =~ "-snapdragon" ]] && [[ ! "$line" =~ "_all" ]] && continue

            line=${line##*href=\"}
            line=${line%%\">*}

            if [ $uses_subfolders -eq 0 ] && [[ $line =~ ${arch}/linux ]]; then
              uses_subfolders=1
            fi

            FILES+=("$line")
        done
        unset IFS

        if [ $check_signature -eq 1 ]; then
            if [ $uses_subfolders -eq 0 ]; then
              FILES+=("CHECKSUMS" "CHECKSUMS.gpg")
            else
              FILES+=("${arch}/CHECKSUMS" "${arch}/CHECKSUMS.gpg")
            fi
        fi

        if [ ${#FILES[@]} -ne $expected_files_count ]; then
            if [ $assume_yes -eq 0 ]; then
                logn "Expected to need to download $expected_files_count files but found ${#FILES[@]}, continue? (y/N)"
                read -rsn1 continue
                echo ""
            else
                continue="y"
            fi

            [ "$continue" != "y" ] && [ "$continue" != "Y" ] && { exit 0; }
        fi

        debs=()
        log "Will download ${#FILES[@]} files from $ppa_host:"
        for file in "${FILES[@]}"; do
            workfile=${file##*/}
            monitor_progress "Downloading $file" "$workdir$workfile"
            download $ppa_host "$ppa_uri$file" > "$workdir$workfile"

            remove_http_headers "$workdir$workfile"
            end_monitor_progress

            if [[ "$workfile" =~ \.deb ]]; then
                debs+=("$workfile")
            fi
        done

        if [ $check_signature -eq 1 ]; then
            if ! gpg --list-keys ${ppa_key} >$debug_target 2>&1; then
                logn "Importing kernel-ppa gpg key "

                if gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv ${ppa_key} >$debug_target 2>&1; then
                    log "ok"
                else
                    logn "failed"
                    warn "Unable to check signature"
                    check_signature=0
                fi
            fi

            if [ $check_signature -eq 1 ]; then
                if gpg --verify CHECKSUMS.gpg CHECKSUMS >$debug_target 2>&1; then
                    log "Signature of checksum file has been successfully verified"
                else
                    err "Abort, signature of checksum file is NOT OK"
                    exit 4
                fi
            fi
        fi

        if [ $check_checksum -eq 1 ]; then
            shasums=( "sha256sum" "sha1sum" )

            for shasum in "${shasums[@]}"; do
                xshasum=$(command -v "$shasum")
                if [ -n "$xshasum" ] && [ -x "$xshasum" ]; then
                    # shellcheck disable=SC2094
                    shasum_result=$($xshasum --ignore-missing -c CHECKSUMS 2>>$debug_target | tee -a $debug_target | wc -l)

                    if [ "$shasum_result" -eq 0 ] || [ "$shasum_result" -ne ${#debs[@]} ]; then
                        err "Abort, $shasum returned an error $shasum_result"
                        exit 4
                    else
                        log "Checksums of deb files have been successfully verified with $shasum"
                    fi

                    break
                fi
            done
        fi

        if [ $do_install -eq 1 ]; then
            if [ ${#debs[@]} -gt 0 ]; then
                log "Installing ${#debs[@]} packages"
                $sudo dpkg -i "${debs[@]}" >$debug_target 2>&1
            else
                warn "Did not find any .deb files to install"
            fi
        else
            log "deb files have been saved to $workdir"
        fi

        if [ $cleanup_files -eq 1 ]; then
            log "Cleaning up work folder"
            rm -f "$workdir"*.deb
            rm -f "$workdir"CHECKSUM*
            rmdir "$workdir"
        fi
        ;;
    uninstall)
        guard_run_as_root
        load_local_versions

        if [ ${#LOCAL_VERSIONS[@]} -eq 0 ]; then
            echo "No installed mainline kernels found"
            exit 1
        elif [ -z "${action_data[0]}" ]; then
            echo "Which kernel version do you wish to uninstall?"
            nr=0
            for version in "${LOCAL_VERSIONS[@]}"; do
                echo "[$nr]: $version"
                nr=$((nr + 1))

                [ $nr -gt 9 ] && break
            done

            echo -n "type the number between []: "
            read -rn1 index
            echo ""

            uninstall_version=${LOCAL_VERSIONS[$index]}
        elif containsElement "v${action_data[0]#v}" "${LOCAL_VERSIONS[@]}"; then
            uninstall_version="v"${action_data[0]#v}
        else
            err "Kernel version ${action_data[0]} not installed locally"
            exit 2
        fi

        if [ $assume_yes -eq 0 ]; then
            echo -n "Are you sure you wish to remove kernel version $uninstall_version? (y/N)"
            read -rsn1 continue
            echo ""
        else
            continue="y"
        fi

        if [ "$continue" == "y" ] || [ "$continue" == "Y" ]; then
            IFS=$'\n'

            pckgs=()
            for pckg in $(dpkg -l linux-{image,image-[un]?signed,headers,modules}-"${uninstall_version#v}"* 2>$debug_target | cut -d " " -f 3); do
                # only match kernels from ppa, they have 6 characters as second version string
                if [[ "$pckg" =~ linux-headers-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{6} ]]; then
                    pckgs+=("$pckg:$arch")
                    pckgs+=("$pckg:all")
                elif [[ "$pckg" =~ linux-(image(-(un)?signed)?|modules)-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{6} ]]; then
                    pckgs+=("$pckg:$arch")
                fi
            done

            if [ ${#pckgs[@]} -eq 0 ]; then
                warn "Did not find any packages to remove"
            else
                echo "The following packages will be removed: "
                echo "${pckgs[@]}"

                if [ $assume_yes -eq 0 ]; then
                    echo -n "Are you really sure? Do you still have another kernel installed? (y/N)"

                    read -rsn1 continue
                    echo ""
                else
                    continue="y"
                fi

                if [ "$continue" == "y" ] || [ "$continue" == "Y" ]; then
                    if $sudo env DEBIAN_FRONTEND=noninteractive dpkg --purge "${pckgs[@]}" 2>$debug_target >&2; then
                        log "Kernel $uninstall_version successfully purged"
                        exit 0
                    fi
                fi
            fi
        fi
        ;;
esac

exit 0
