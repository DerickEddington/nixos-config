{ pkgs }:

pkgs.writeShellScriptBin "with-unhidden-gitdir" ''

# A command that unhides and re-hides a .git in the current directory.
#
# with-unhidden-gitdir runs a given command (or the user's VISUAL editor if no
# command is given) with a ./.git restored temporarily, so that Git and other
# things like Magit will see the current directory as a repository during the
# execution of the command.  When the command finishes, the ./.git is removed so
# that it is hidden again.  This is achieved by creating the ./.git as a symlink
# to a ./.git-hidden that is the actual GIT_DIR and which is assumed to exist.
#
# The motivating case for this is for a user to be able to temporarily work with
# their ~/.dotfiles repository and the checkout of its files in their ~/, as
# setup by our setup-home script.  Most of the time, a user does not want their
# home directory to be seen by Git as a repository, and so setup-home moves the
# initial ~/.git (which just refers to ~/.dotfiles) to ~/.git-hidden.
#
# Note that when using this you must be careful to consider the effect on other
# things of making the directory become a Git repository for a span of time.
# E.g. if you have an Emacs already running with Magit, then it will handle the
# directory as a repository while the temporary unhidding is in effect, which
# could be unexpected and undesired, so be careful.

set -o errexit -o nounset

function fail {
    echo "Error:" "$@" 1>&2
    exit 1
}


if [ $# -ge 1 ]; then
  COMMAND=("$@")
else
  COMMAND=($VISUAL)
fi;

[ -e .git-hidden ] || fail "Missing .git-hidden"
[ -e .git ] && fail "Pre-existing .git"


${pkgs.coreutils}/bin/ln -s .git-hidden .git

# Run the user's command like this, so that if it returns a failure status code
# then we continue executing to remove the .git, and to prevent it from being
# affected by the shell options we set.
( set +o errexit +o nounset
  "''${COMMAND[@]}"
) && :
EXIT_STATUS=$?

${pkgs.coreutils}/bin/rm .git

exit $EXIT_STATUS
''
