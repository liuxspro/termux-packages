#!/bin/bash
set -euo pipefail

# Podman variant of 'scripts/run-docker.sh' for running the Termux package
# builder container with podman instead of docker, e.g. with the
# 'podman-docker' compatibility package installed.
#
# Differences to 'run-docker.sh':
# - Uses 'podman' instead of 'docker'.
# - No AppArmor support: podman does not support custom AppArmor profiles like
#   docker does. Containers are confined with the seccomp profile and SELinux
#   labels instead (plus the user namespace when running rootless).
# - When running rootless, '--userns=keep-id:uid=1001,gid=1001' is used to map
#   the host user onto the 'builder' user (uid/gid 1001) inside the container,
#   so files created in mounted directories are owned by the host user without
#   changing the builder uid/gid. Note that with rootless podman, chowning
#   files to an uid that is not mapped into the container would map to an
#   unrelated subordinate uid on the host (see /etc/subuid) and break the
#   file ownership of the host user, so only the mapped builder uid is used.
# - 'builder' is passed explicitly to 'podman run'/'podman exec' since
#   '--userns=keep-id' overrides the default user of the image.
# - Whether '--init' is usable is probed at container creation, as podman
#   needs an init helper binary (catatonit) for it which is not installed
#   everywhere.
#
# The environment variable name DOCKER_EXEC_PID_FILE_PATH is intentionally
# kept as it is the contract with build-package.sh, which stores its pid there
# via docker__create_docker_exec_pid_file().

TERMUX_SCRIPTDIR=$(cd "$(realpath "$(dirname "$0")")"; cd ..; pwd)
: ${TERMUX_BUILDER_IMAGE_NAME:=ghcr.io/termux/package-builder}
: ${CONTAINER_NAME:=termux-package-builder}
# The TERMUX_DOCKER_* variables of 'run-docker.sh' are accepted as fallbacks.
: ${TERMUX_PODMAN_RUN_EXTRA_ARGS:=${TERMUX_DOCKER_RUN_EXTRA_ARGS:-}}
: ${TERMUX_PODMAN_EXEC_EXTRA_ARGS:=${TERMUX_DOCKER_EXEC_EXTRA_ARGS:-}}
: ${TERMUX_PODMAN_USE_SUDO:=${TERMUX_DOCKER_USE_SUDO:-}}
PODMAN=podman
BUILDSCRIPT_NAME=build-package.sh
CONTAINER_HOME_DIR=/home/builder

if ! command -v $PODMAN > /dev/null 2>&1; then
	echo "Error: '$PODMAN' not found in 'PATH'" 1>&2
	exit 1
fi

_show_usage() {
	echo "Usage: $0 [OPTIONS] [COMMAND]"
	echo ""
	echo "Run a command in the Termux package builder container using podman. If no command is given, an interactive shell will be started."
	echo ""
	echo "Options:"
	echo "  -h, --help                 Show this help message and exit"
	echo "  -d, --dry-run              Run 'build-package-dry-run-simulation.sh' before"
	echo "                             building any package. This is useful for CI to"
	echo "                             skip unnecessary podman runs."
	echo "  -m, --mount-termux-dirs    Mount /data and ~/.termux-build into the container."
	echo "                             This is useful for building locally for development"
	echo "                             with host IDE and editors."
	echo "Supported environment variables:"
	echo "  TERMUX_BUILDER_IMAGE_NAME      The name of the podman image to use"
	echo "  CONTAINER_NAME                 The name of the podman container to create/use"
	echo "  TERMUX_PODMAN_RUN_EXTRA_ARGS   Extra arguments to pass to 'podman run' while"
	echo "                                 creating the container"
	echo "  TERMUX_PODMAN_EXEC_EXTRA_ARGS  Extra arguments to pass to 'podman exec' while"
	echo "                                 running the command in the container"
	echo "  TERMUX_PODMAN_USE_SUDO         If set to any non-empty value, 'sudo' will be"
	echo "                                 used to run 'podman' commands"
	echo ""
	echo "The corresponding TERMUX_DOCKER_* variables of 'run-docker.sh' are accepted"
	echo "as fallbacks."
	echo ""
	echo ""
	echo "Kindly note that:"
	echo "- TERMUX_PODMAN_RUN_EXTRA_ARGS is only considered when creating the container,"
	echo "  and will not be applied when running the command in the container if the"
	echo "  container already exists."
	echo "- To apply new TERMUX_PODMAN_RUN_EXTRA_ARGS, the existing container needs to be"
	echo "  removed first."
	echo "- The above rules also apply to -m/--mount-termux-dirs option as it adds the"
	echo "  mount arguments to TERMUX_PODMAN_RUN_EXTRA_ARGS."
	echo "- The dry-run option will only work if the first argument passed to this script"
	echo "  which runs podman contains '$BUILDSCRIPT_NAME', and it will run"
	echo "  'build-package-dry-run-simulation.sh' with arguments passed to this script."
	exit 0
}

dry_run="false"

while (( $# != 0 )); do
	case "$1" in
		-h|--help) shift 1; _show_usage;;
		-d|--dry-run)
			dry_run="true"
			shift 1;;
		-m|--mount-termux-dirs)
			TERMUX_PODMAN_RUN_EXTRA_ARGS="--volume /data:/data --volume $HOME/.termux-build:$CONTAINER_HOME_DIR/.termux-build $TERMUX_PODMAN_RUN_EXTRA_ARGS"
			shift 1;;
		--) shift 1; break;;
		-*) echo "Error: Unknown option '$1'" 1>&2; shift 1; exit 1;;
		*) break;;
	esac
done

# If 'build-package-dry-run-simulation.sh' does not return 85 (EX_C__NOOP), or if
# $1 (the first argument passed to this script which runs podman) does not contain
# $BUILDSCRIPT_NAME, this condition will evaluate false and this script which
# runs podman will continue.
if [ "${dry_run}" = "true" ]; then
	case "${1:-}" in
		*"/$BUILDSCRIPT_NAME")
			RETURN_VALUE=0
			OUTPUT="$("$TERMUX_SCRIPTDIR/scripts/bin/build-package-dry-run-simulation.sh" "$@" 2>&1)" || RETURN_VALUE=$?
			if [ $RETURN_VALUE -ne 0 ]; then
				echo "$OUTPUT" 1>&2
				if [ $RETURN_VALUE -eq 85 ]; then # EX_C__NOOP
					echo "$0: Exiting since '$BUILDSCRIPT_NAME' would not have built any packages"
					exit 0
				fi
				exit $RETURN_VALUE
			fi
			;;
	esac
fi

UNAME=$(uname)
if [ "$UNAME" = Darwin ]; then
	# Workaround for mac readlink not supporting -f.
	REPOROOT=$PWD
	SEC_OPT=""
else
	REPOROOT="$(dirname $(readlink -f $0))/../"
	SEC_OPT=" --security-opt seccomp=$REPOROOT/scripts/profile.json --cap-add CAP_SYS_ADMIN --device /dev/fuse"
fi

if [ "${CI:-}" = "true" ]; then
	CI_OPT="--env CI=true"
else
	CI_OPT=""
fi

# Required for Linux with SELinux and btrfs to avoid permission issues, eg: Fedora
# To reset, use "restorecon -Fr ."
# To check, use "ls -Z ."
if [ -n "$(command -v getenforce)" ] && [ "$(getenforce)" = Enforcing ]; then
	VOLUME=$REPOROOT:$CONTAINER_HOME_DIR/termux-packages:z
else
	VOLUME=$REPOROOT:$CONTAINER_HOME_DIR/termux-packages
fi

if [ -n "${TERMUX_PODMAN_USE_SUDO-}" ]; then
	SUDO="sudo"
else
	SUDO=""
fi

echo "Running container '$CONTAINER_NAME' from image '$TERMUX_BUILDER_IMAGE_NAME' with '$PODMAN'..."

# Check whether attached to tty and adjust podman flags accordingly.
if [ -t 1 ]; then
	DOCKER_TTY=" --tty"
else
	DOCKER_TTY=""
fi

# Detect rootless podman. In rootless mode container uids/gids are mapped to
# subordinate ids of the host user (see /etc/subuid and /etc/subgid), so the
# host user is mapped onto the builder user with '--userns=keep-id:uid=1001,
# gid=1001' to keep the file ownership on mounted directories correct.
ROOTLESS="false"
if [ "$UNAME" != Darwin ] && [ "$($SUDO $PODMAN info --format '{{.Host.Security.Rootless}}' 2> /dev/null || echo false)" = "true" ]; then
	ROOTLESS="true"
fi

if [ "$ROOTLESS" = "true" ]; then
	USERNS_OPT="--userns=keep-id:uid=1001,gid=1001"
else
	USERNS_OPT=""
fi

__change_builder_uid_gid() {
	if [ "$UNAME" != Darwin ]; then
		if [ "$ROOTLESS" = "true" ]; then
			# The builder user is already mapped onto the host user by
			# '--userns=keep-id:uid=1001,gid=1001', so no uid/gid change is
			# needed. Only ensure that files in the mounted directories are
			# usable by builder. Files are chowned to the mapped builder uid,
			# so ownership on the host stays with the host user. This is best
			# effort as files owned by uids not mapped into the container,
			# e.g. the host root, cannot be chowned from a user namespace.
			echo "Ensuring builder ownership of $CONTAINER_HOME_DIR and /data... (this may take a while)"
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo chown -R builder:builder $CONTAINER_HOME_DIR || \
				echo "WARNING: Failed to fully change ownership of $CONTAINER_HOME_DIR, files owned by uids not mapped into the container cannot be chowned by rootless podman"
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo chown -R builder:builder /data || \
				echo "WARNING: Failed to fully change ownership of /data, files owned by uids not mapped into the container cannot be chowned by rootless podman"
		elif [ $(id -u) -ne 1001 -a $(id -u) -ne 0 ]; then
			echo "Changed builder uid/gid... (this may take a while)"
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo chown -R $(id -u):$(id -g) $CONTAINER_HOME_DIR
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo chown -R $(id -u):$(id -g) /data
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo usermod -o -u $(id -u) builder
			$SUDO $PODMAN exec $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME sudo groupmod -o -g $(id -g) builder
		fi
	fi
}

__change_container_pid_max() {
	if [ "$UNAME" != Darwin ]; then
		echo "Changing /proc/sys/kernel/pid_max to 65535 for packages that need to run native executables using proot (for 32-bit architectures)"
		if [[ "$($SUDO $PODMAN exec $CONTAINER_NAME cat /proc/sys/kernel/pid_max)" -le 65535 ]]; then
			echo "No need to change /proc/sys/kernel/pid_max, current value is $($SUDO $PODMAN exec $DOCKER_TTY $CONTAINER_NAME cat /proc/sys/kernel/pid_max)"
		else
			# On kernel versions >= 6.14, the pid_max value is pid namespaced, so we need to set it in the container namespace instead of host.
			# But some distributions may backport the pid namespacing to older kernels, so we check whether it's effective by checking the value in the container after setting it.
			$SUDO $PODMAN run --privileged --pid="container:$CONTAINER_NAME" --rm "$TERMUX_BUILDER_IMAGE_NAME" sh -c "echo 65535 | sudo tee /proc/sys/kernel/pid_max > /dev/null" || :
			if [[ "$($SUDO $PODMAN exec $CONTAINER_NAME cat /proc/sys/kernel/pid_max)" -eq 65535 ]]; then
				echo "Successfully changed /proc/sys/kernel/pid_max for container namespace"
			elif [ "$ROOTLESS" = "true" ]; then
				echo "Failed to change /proc/sys/kernel/pid_max for container, changing it on the host requires root and is not attempted with rootless podman, some packages that need to run native executables using proot (for 32-bit architectures) may not work properly"
			else
				echo "Failed to change /proc/sys/kernel/pid_max for container, falling back to setting it on host..."
				if ( echo 65535 | $SUDO tee /proc/sys/kernel/pid_max >/dev/null ); then
					echo "Successfully changed /proc/sys/kernel/pid_max on host, but it may affect other processes on the host system"
				else
					echo "Failed to change /proc/sys/kernel/pid_max on host as well, some packages that need to run native executables using proot (for 32-bit architectures) may not work properly"
				fi
			fi
		fi
	fi
}


if ! $SUDO $PODMAN container inspect $CONTAINER_NAME > /dev/null 2>&1; then
	echo "Creating new container..."
	# Probe whether '--init' is usable, as podman needs an init helper binary
	# like 'catatonit' for it which is not installed everywhere.
	INIT_OPT="--init"
	if ! $SUDO $PODMAN run --rm --init "$TERMUX_BUILDER_IMAGE_NAME" true > /dev/null 2>&1; then
		echo "WARNING: Running without '--init' as no usable init helper (like 'catatonit') was found,"
		echo "         zombie processes may not be reaped properly in the container"
		INIT_OPT=""
	fi
	$SUDO $PODMAN run \
		--detach \
		$INIT_OPT \
		--name $CONTAINER_NAME \
		--user builder \
		--volume $VOLUME \
		$USERNS_OPT \
		$SEC_OPT \
		--tty \
		$TERMUX_PODMAN_RUN_EXTRA_ARGS \
		$TERMUX_BUILDER_IMAGE_NAME
	__change_builder_uid_gid
	__change_container_pid_max
fi

if [[ "$($SUDO $PODMAN container inspect -f '{{ .State.Running }}' $CONTAINER_NAME)" == "false" ]]; then
	$SUDO $PODMAN start $CONTAINER_NAME >/dev/null 2>&1
	__change_container_pid_max
fi

# Set traps to ensure that the process started with podman exec and all its
# children are killed. This is the podman variant of the traps set up by
# docker__setup_docker_exec_traps() in 'scripts/utils/docker/docker.sh', which
# is not used here as it calls 'docker' directly.
__run_podman_exec_trap() {
	local exit_code=$? # Store the original trap exit code
	local signal="${1:-}";
	trap - EXIT  # Remove the EXIT trap so its not called again

	if [ -n "$signal" ]; then
		trap - "$signal"; # If a signal argument was passed, then remove its trap
	fi

	if [ -n "${CONTAINER_NAME-}" ] && [ -n "${DOCKER_EXEC_PID_FILE_PATH-}" ]; then

		local podman_exec_trap_command='
# If called process did not store its pid in file path, then just exit
[ ! -f '"$DOCKER_EXEC_PID_FILE_PATH"' ] && exit 0;

killtree() {
    local signal="${1:-}"; local pid="${2:-}"; local cpid
    for cpid in $(pgrep -P "$pid"); do killtree "$signal" "$cpid"; done
    [[ "$pid" != "$$" ]] && kill "-${signal:-15}" "$pid" 2>/dev/null || :
}

# Read the pid stored in file path and send kill signals to the process and all its children
PODMAN_PID="$(cat '"$DOCKER_EXEC_PID_FILE_PATH"')" && [[ "$PODMAN_PID" =~ ^[0-9]+$ ]] && \
killtree "'"$signal"'" "$PODMAN_PID" || :
        '
        # Exec podman_exec_trap_command inside podman context
        $SUDO $PODMAN exec "$CONTAINER_NAME" bash -c "$podman_exec_trap_command" || :

    fi

    exit $exit_code # Exit with the original trap exit code

}

DOCKER_EXEC_PID_FILE_PATH="/tmp/docker-exec-pid-$(date +"%Y-%m-%d-%H.%M.%S.")$((RANDOM%1000))"
trap '__run_podman_exec_trap' EXIT
trap '__run_podman_exec_trap TERM' TERM
trap '__run_podman_exec_trap INT' INT
trap '__run_podman_exec_trap HUP' HUP
trap '__run_podman_exec_trap QUIT' QUIT

if [ "$#" -eq "0" ]; then
	set -- bash
fi

$SUDO $PODMAN exec $CI_OPT --env "DOCKER_EXEC_PID_FILE_PATH=$DOCKER_EXEC_PID_FILE_PATH" --interactive $DOCKER_TTY $TERMUX_PODMAN_EXEC_EXTRA_ARGS --user builder $CONTAINER_NAME "$@"
