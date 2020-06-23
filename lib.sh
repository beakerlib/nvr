#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/distribution/Library/nvr
#   Description: Library allows easily compare NVR of an installed package
#   Author: Karel Srot <ksrot@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = nvr
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

distribution/nvr - Library allows easily compare NVR of an installed package

=head1 DESCRIPTION

The library provides functions for testing version of an installed RPM
package. Unlike rlCmpVersion and rlTestVersion the library separates package
Version, Release and Dist tag allowing comfortable and compact notation,
following RPM NVR arithmetics.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 VARIABLES

Below is the list of global variables. When writing a new library,
please make sure that all global variables start with the library
prefix to prevent collisions with other libraries.

=over

=item nvrPYTHON_BINARY

Path to the Python interpreter.

=back

=cut

if [ -z "$nvrPYTHON_BINARY" ]; then  # auto-detect nvrPYTHON_BINARY
  nvrPYTHON_BINARY="/usr/bin/env python"
  if rpm -q python3-rpm &> /dev/null; then
    if [ -e /usr/libexec/platform-python ]; then
      nvrPYTHON_BINARY="/usr/libexec/platform-python"
    elif [ -e /usr/bin/python3 ]; then
      nvrPYTHON_BINARY="/usr/bin/python3"
    fi
  elif rpm -q rpm-python &> /dev/null || rpm -q python2-rpm &> /dev/null; then
    if [ -e /usr/bin/python2 ]; then
      nvrPYTHON_BINARY="/usr/bin/python2"
    elif [ -e /usr/bin/python ]; then
      nvrPYTHON_BINARY="/usr/bin/python"
    fi
  fi
fi

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=cut


# separates Epoch, Version, Release from E:V-R format
__nvrParseEVR() {
  local EVR="$1";
  local EPOCH="";
  local VER="";
  local REL="";
  if [ -z ${EVR##*-*} ]; then   # there is both VERSION and RELEASE
    VER=${EVR%%-*}
    REL=${EVR#*-}
  else
    VER="$EVR"
    REL=""
  fi
  if [ -z ${VER##*:*} ]; then   # there is both EPOCH and VERSION
    EPOCH=${VER%%:*}
    VER=${VER#*:}
  fi
  if [ -z "$EPOCH" ]; then
    EPOCH="(none)"
  fi
  echo "$EPOCH" "$VER" "$REL"
  return 0
};


# The function takes 2 parameters
#   package name (optionally even NEVRA)
#   VERSIONSPEC (subset of EVR) to compare against
#       format: VERSION[-RELEASE[.DIST]]
# The function gets EVR of the installed package and takes subset
# of the information so there is a parity in epoch, version, release,
# and dist tag presence with VERSIONSPEC data specified in the 2nd argument
# The function returns two normalized arguments to the STDOUT,
# these are going to be passed to respective test functions.
#
# Optinally it takes --dist option having one argument - an expression
# (with wildcards) that should match the entire package dist tag.
# If dist tag won't match, the fuction exits with exit code 3.
__nvrNormalizePackageEVR() {
  local DIST_EXP;
  if [ "$1" == "--dist" ]; then
    rlLogDebug "$FUNCNAME(): '--dist' parameter passed with argument '$2'"
    DIST_EXP="$2"
    shift 2
    if [ -z "$DIST_EXP" ]; then
      echo "Error: No argument passed to the --dist option" 1>&2
      exit 4
    fi
  fi
  local PKG="$1"
  local EVR="$2"
  rlLogDebug "$FUNCNAME(): Normalizing package '$1' according to '$2'"
  local TESTVER="";
  local TESTREL="";
  local TESTDIST="";
  local PKGNAME="";
  local PKGVER="";
  local PKGRELEASE="";
  local PKGREL="";
  local PKGDIST="";
  local RESULT="";

  if [ -z "$PKG" ] || [ -z "$EVR" ]; then
    echo "Error: Incorrect parameters" 1>&2
    return 4
  fi

  # check that the package is installed and make sure we have proper name
  if ! rpm -q $PKG &> /dev/null; then
    echo "Error: Package $PKG is not installed" 1>&2
    return 4
  fi

  PKGEPOCH=$( rpm -q --qf '%{EPOCH}' $PKG | head -1 )
  rlLogDebug "$FUNCNAME(): Installed package Epoch '$PKGEPOCH'"
  PKGVER=$( rpm -q --qf '%{VERSION}' $PKG | head -1 )
  rlLogDebug "$FUNCNAME(): Installed package Version '$PKGVER'"
  PKGRELEASE=$( rpm -q --qf '%{RELEASE}' $PKG | head -1 )
  rlLogDebug "$FUNCNAME(): Installed package Release '$PKGRELEASE'"
  PKGREL=${PKGRELEASE%%\.*}
  rlLogDebug "$FUNCNAME(): Installed package plain Release '$PKGREL'"
  PKGDIST="${PKGRELEASE#*\.}"
  rlLogDebug "$FUNCNAME(): Installed package Dist tag '$PKGDIST'"

  if [ -n "$DIST_EXP" ]; then  # matching the dist tag
    rlLogDebug "$FUNCNAME(): Does Dist tag '$PKGDIST' match with '$DIST_EXP'?"
    if [ -n "${PKGDIST##$DIST_EXP}" ]; then  # DIST_EXP does not matches
      rlLogDebug "$FUNCNAME(): Dist tag '$PKGDIST' does not match with '$DIST_EXP'"
      return 3
    else
      rlLogDebug "$FUNCNAME(): Dist tag '$PKGDIST' does match with '$DIST_EXP'"
    fi
  fi

  # check for - in EVR
  rlLogDebug "$FUNCNAME(): Does '$EVR' specifies both Version and Release?"
  if [ -z ${EVR##*-*} ]; then   # there is both VERSION and RELEASE
    TESTVER=${EVR%%-*}
    rlLogDebug "$FUNCNAME(): Does '$TESTVER' specifies both Epoch and Version?"
    if [ -z ${EVR##*:*} ]; then   # there is both EPOCH and VERSION
      PKGVER="$PKGEPOCH:$PKGVER"
    fi
    TESTRELEASE=${EVR#*-}
    # check if we have dist tag included
    rlLogDebug "$FUNCNAME(): Does '$TESTRELEASE' specifies a Dist tag?"
    if [ -z ${TESTRELEASE##*\.*} ]; then   # there is a DIST tag
      TESTREL=${TESTRELEASE%%\.*}
      TESTDIST=${TESTRELEASE#*\.}
      rlLogDebug "$FUNCNAME(): Version, Release, Dist specified, parsed as '$TESTVER' '$TESTREL' '$TESTDIST'"
      RESULT="${PKGVER}-${PKGREL}.${PKGDIST} ${TESTVER}-${TESTREL}.${TESTDIST}"
    else  # no DIST tag
      TESTREL=$TESTRELEASE
      rlLogDebug "$FUNCNAME(): Only Version and Release specified, parsed as '$TESTVER' '$TESTREL'"
      RESULT="$PKGVER-$PKGREL $TESTVER-$TESTREL"
    fi
  else  # only VERSION was passed
    TESTVER="$EVR"
    rlLogDebug "$FUNCNAME(): Does '$TESTVER' specifies both Epoch and Version?"
    if [ -z ${EVR##*:*} ]; then   # there is both EPOCH and VERSION
      PKGVER="$PKGEPOCH:$PKGVER"
    fi
    rlLogDebug "$FUNCNAME(): Only Version specified, parsed as '$TESTVER'"
    RESULT="$PKGVER $TESTVER"
  fi
  rlLogDebug "$FUNCNAME(): Normalized arguments: $RESULT"
  echo $RESULT
  return 0
};


true <<'=cut'
=head2 nvrCompareEVR

Compares two version numbers specified in the EVR format

  nvrCompareEVR version1 version2

Function calls rpm.labelCompare function directly and
does not do any argument pre-processing.

=over

=item version

Version specification in the EVR format:

  [EPOCH:]VERSION[-RELEASE]

=back

Returns 0 when versions are equal.
Returns 1 if version1 > version2.
Retruns 2 if version1 < version2.

=cut

# compares two EVRs
nvrCompareEVR() {
  local PKG1=( $( __nvrParseEVR "$1" ) )
  local PKG2=( $( __nvrParseEVR "$2" ) )
  # evaluate using python rpm.labelCompare
  local RES=$( $nvrPYTHON_BINARY -c "import rpm; \
    print(rpm.labelCompare( \
      ('${PKG1[0]}', '${PKG1[1]}', '${PKG1[2]}'), \
      ('${PKG2[0]}', '${PKG2[1]}', '${PKG2[2]}') \
    )) \
  ")
  [ "$RES" == "0" ] && return 0
  [ "$RES" == "-1" ] && return 2
  [ "$RES" == "1" ] && return 1
};

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nvrComparePackage
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head2 nvrComparePackage

Compares the version of an installed package specified by name with the
version passed as an argument.

    nvrComparePackage name version

Optionally, accepts --dist option with an argument that is matched against
the dist tag.

    nvrComparePackageEVR --dist dist name version

=over

=item name

Name of an installed package, specific NEVRA is also accepted.

=item version

Version to tests against, provided in the following format

    [EPOCH:]VERSION[-RELEASE[.DIST]]

Examples:

    nvrComparePackage bash 1.2.0
    nvrComparePackage bash 1.2.0-2
    nvrComparePackage bash 1.2.0-2.el8

=item dist

Pattern (can contain wildcards) to be matched against the complete dist tag
of an installed package.

Examples:

    nvrComparePackage --dist 'el8*' bash 1.2.0

=back

Returns 0 if the install package has the matching version, sign '=' is printed
to stdout.
Returns 1 if the version of an installed package is higher, sign '>' is printed
to stdout.
Returns 2 if the version of an installed package is lower, sign '<' is printed
to stdout.
Returns 3 if the dist tag did not match the pattern, sign '!' is printed
to stdout.
Returns 4 in case of an error, sign '!' is printed to stdout.

=cut

nvrComparePackage() {
  local NORMALIZED_ARGS;
  local EX;
  local RET;
  local VAL;
  rlLogDebug "$FUNCNAME(): Normalizing arguments: $( echo "$@" )"
  NORMALIZED_ARGS=( $( __nvrNormalizePackageEVR "$@" ) )
  EX=$?
  VAL='!'
  if [ $EX -eq 0 ]; then
    rlLogDebug "$FUNCNAME(): Calling nvrCompareEVR $( echo ${NORMALIZED_ARGS[@]} )"
    nvrCompareEVR ${NORMALIZED_ARGS[@]}
    EX=$?
    [ $EX -eq 0 ] && VAL='='
    [ $EX -eq 1 ] && VAL='>'
    [ $EX -eq 2 ] && VAL='<'
    rlLogDebug "$FUNCNAME(): Relation is '$VAL'"
    RET=$EX
  elif [ $EX -eq 3 ]; then
    rlLogDebug "$FUNCNAME(): Dist tag matching failed"
    RET=3
  else
    rlLogDebug "$FUNCNAME(): Normalization failed"
    RET=4
  fi
  echo "$VAL"
  return $RET
};


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# nvrTestPackage
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
: <<'=cut'
=pod

=head3 nvrTestPackage

Test relation between the version of an installed package and a version passed
as an argument.

    nvrTestPackage name op version

Optionally, accepts --dist option with an argument that is matched against
the dist tag.

    nvrTestPackage --dist dist name op version

=over

=item name

Name of an installed package, specific NEVRA is also accepted.

=item op

Operator defining the logical expression.
It can be '=', '==', '!=', '<', <=', '=<', '>', '>=', '=>' or
2-letter shortcuts '-eq', '-ne', '-lt', '-le', '-gt', '-ge'.

=item version

Version to tests against, provided in the following format

    VERSION[-RELEASE[.DIST]]

Examples:

    nvrTestPackage bash '>=' 1.2.0
    nvrTestPackage bash '!=' 1.2.0-2
    nvrTestPackage bash -eq 1.2.0-2.el8_1

=item dist

Pattern (can contain wildcards) to be matched against the complete dist tag
of an installed package.

Examples:

    nvrTestPackage --dist 'el8*' bash '>=' 1.2.0

=back

Returns 0 if the expresison ver1 op ver2 is true.
Returns 1 if the expression is false.
Returns 3 if the dist tag did not match the pattern.
Returns 4 in case of an error.

=cut

function nvrTestPackage() {
  local OP;
  local RET;
  local EX;
  if [ "$1" == "--dist" ]; then
    OP=$4;
    set -- "${@:1:3}" "${@:5:5}"
  else
    OP=$2;
    set -- "${@:1:1}" "${@:3:3}"
  fi
  local NORMALIZED_ARGS;
  rlLogDebug "$FUNCNAME(): Normalizing reordered arguments: $( echo "$@" )"
  NORMALIZED_ARGS=( $( __nvrNormalizePackageEVR "$@" ) )
  EX=$?
  if [ $EX -eq 0 ]; then
    rlLogDebug "$FUNCNAME(): Calling nvrCompareEVR $( echo ${NORMALIZED_ARGS[@]} )"
    nvrCompareEVR $( echo ${NORMALIZED_ARGS[@]} )
    EX=$?
    rlLogDebug "$FUNCNAME(): nvrCompareEVR returned $EX"
    if [ $EX -eq 0 ]; then  # equal
      [ "$OP" == "=" -o "$OP" == "==" -o "$OP" == ">=" -o "$OP" == "<=" -o "$OP" == "=<" -o "$OP" == "=>" \
        -o "$OP" == "-eq" -o "$OP" == "-ge" -o "$OP" == "-le" ] && \
        RET=0 || RET=1
    elif [ $EX -eq 1 ]; then  # pkg > EVR
      [ "$OP" == ">" -o "$OP" == ">=" -o "$OP" == "=>" -o "$OP" == "!=" \
        -o "$OP" == "-gt" -o "$OP" == "-ge" -o "$OP" == "-ne" ] && \
        RET=0 || RET=1
    elif [ $EX -eq 2 ]; then  # pkg < EVR
      [ "$OP" == "<" -o "$OP" == "<=" -o "$OP" == "=<" -o "$OP" == "!=" \
        -o "$OP" == "-lt" -o "$OP" == "-le" -o "$OP" == "-ne" ] && \
        RET=0 || RET=1
    else 
      rlLogDebug "$FUNCNAME(): Unexpected return value $EX, returning failure"
      RET=4
    fi
    [ $RET -eq 0 ] && rlLogDebug "$FUNCNAME(): Result is 'true'"
    [ $RET -eq 1 ] && rlLogDebug "$FUNCNAME(): Result is 'false'"
    rlLogDebug "$FUNCNAME(): Return value is $RET"
    return $RET
  elif [ $EX -eq 3 ]; then
    rlLogDebug "$FUNCNAME(): Dist tag matching failed"
    return 3
  else
    rlLogDebug "$FUNCNAME(): Normalization failed, returning failure"
    return 4
  fi
}

true <<'=cut'
=pod

=head1 EXECUTION

This library supports direct execution. When run as a task, phases
provided in the PHASE environment variable will be executed.
Supported phases are:

=over

=item Test

Run the self test suite.

=back

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is a verification callback which will be called by
#   rlImport after sourcing the library to make sure everything is
#   all right. It makes sense to perform a basic sanity test and
#   check that all required packages are installed. The function
#   should return 0 only when the library is ready to serve.

nvrLibraryLoaded() {
    if [ -z "$nvrPYTHON_BINARY" ]; then
        rlLogError "Could not find python binary, please export nvrPYTHON_BINARY variable."
        return 1
    elif ! $nvrPYTHON_BINARY --version; then
        rlLogError "Could not execute python binary at $nvrPYTHON_BINARY, please export nvrPYTHON_BINARY variable."
        return 1
    elif ! $nvrPYTHON_BINARY -c 'import rpm'; then
        rlLogError "Could not import rpm Python module."
        return 1
    else
        rlLogDebug "Succesfully executed Python binary at $nvrPYTHON_BINARY"
        return 0
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Karel Srot <ksrot@redhat.com>

=back

=cut
