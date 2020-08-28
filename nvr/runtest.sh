#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/distribution/Library/nvr
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="distribution"
PHASE=${PHASE:-Test}

assertTrue() {
    local comment="$1"
    local command="$2"
    rlRun "$command" 0 "$comment"
}

assertFalse() {
    local comment="$1"
    local command="$2"
    local expects="${3:-1}"
    rlRun "$command" "$expects" "$comment"
}


test_nvrComparePackage() {
  local exp_res=0 res res_part ver1 ver2 op op2
  local PKG_N=bash
  local PKG_E=$( rpm -q --qf '%{EPOCH}' $PKG_N )
  local PKG_V=$( rpm -q --qf '%{VERSION}' $PKG_N )
  local PKG_RELEASE=$( rpm -q --qf '%{RELEASE}' $PKG_N )
  local PKG_R=${PKG_RELEASE%%\.*}
  local PKG_D="${PKG_RELEASE#*\.}"
  local tmpfile=$( mktemp )

  cat > $tmpfile <<EOF
0  $PKG_N            =  $PKG_V
1  $PKG_N            >  0.1
2  $PKG_N            <  999
0  $PKG_N            =  $PKG_V-$PKG_R
1  $PKG_N            >  $PKG_V-0
2  $PKG_N            <  $PKG_V-999
0  $PKG_N            =  $PKG_V-$PKG_R.$PKG_D
2  $PKG_N            <  $PKG_V-$PKG_R.${PKG_D}_1
1  $PKG_N            >  $PKG_V-$PKG_R.AA
2  $PKG_N            <  $PKG_V-$PKG_R.zz
0  $PKG_N            =  $PKG_E:$PKG_V
2  $PKG_N            <  999:$PKG_V
EOF

  while read -r exp_res ver1 op ver2; do
    rlLogInfo "testing nvrComparePackage '$ver1' '$ver2'"
    op2=$(nvrComparePackage "$ver1" "$ver2")
    res=$?
    assertTrue "test exit code" "[[ '$res' == '$exp_res' ]]"
    assertTrue "test printed character" "[[ '$op' == '$op2' ]]"
  done < $tmpfile
  rm $tmpfile

  # few asserts for --dist option
  rlLogInfo "testing nvrComparePackage --dist '\*' '$PKG_N' '$PKG_V'"
  op2=$(nvrComparePackage --dist '*' "$PKG_N" "$PKG_V")
  res=$?
  assertTrue "test exit code" "[[ '$res' == '0' ]]"
  assertTrue "test printed character" "[[ '$op2' == '=' ]]"

  rlLogInfo "testing nvrComparePackage --dist 'zz' '$PKG_N' '$PKG_V'"
  op2=$(nvrComparePackage --dist 'zz' "$PKG_N" "$PKG_V")
  res=$?
  assertTrue "test exit code" "[[ '$res' == '3' ]]"
  assertTrue "test printed character" "[[ '$op2' == '!' ]]"
}

test_nvrTestPackage() {
  local exp_res=0 res res_part ver1 ver2 op op2
  local PKG_N=bash
  local PKG_V=$( rpm -q --qf '%{VERSION}' $PKG_N )
  local PKG_RELEASE=$( rpm -q --qf '%{RELEASE}' $PKG_N )
  local PKG_R=${PKG_RELEASE%%\.*}
  local PKG_D="${PKG_RELEASE#*\.}"
  local tmpfile=$( mktemp )

  cat > $tmpfile <<EOF
0  $PKG_N            =  $PKG_V
0  $PKG_N            -eq  $PKG_V
0  $PKG_N            >  0.1
0  $PKG_N            -gt  0.1
1  $PKG_N            =  0.1
0  $PKG_N            <  999
0  $PKG_N            -lt  999
1  $PKG_N            <  $PKG_V
1  $PKG_N            -ne  $PKG_V
0  $PKG_N            =  $PKG_V-$PKG_R
0  $PKG_N            -ge  $PKG_V-$PKG_R
0  $PKG_N            -le  $PKG_V-$PKG_R
1  $PKG_N            >  $PKG_V-$PKG_R
0  $PKG_N            >  $PKG_V-0
0  $PKG_N            <  $PKG_V-999
1  $PKG_N            =  $PKG_V-999
0  $PKG_N            =  $PKG_V-$PKG_R.$PKG_D
1  $PKG_N            <  $PKG_V-$PKG_R.$PKG_D
0  $PKG_N            <  $PKG_V-$PKG_R.${PKG_D}_1
1  $PKG_N            =  $PKG_V-$PKG_R.${PKG_D}_1
0  $PKG_N            >  $PKG_V-$PKG_R.AA
0  $PKG_N            <  $PKG_V-$PKG_R.zz
EOF

  while read -r exp_res ver1 op ver2; do
    rlLogInfo "testing nvrTestPackage '$ver1' '$op' '$ver2'"
    op2=$( nvrTestPackage "$ver1" "$op" "$ver2" )
    res=$?
    assertTrue "test exit code" "[[ '$res' == '$exp_res' ]]"
  done < $tmpfile
  rm $tmpfile
}


rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport distribution/nvr"
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
    rlPhaseEnd

    # Self test
    if [[ "$PHASE" =~ "Test" ]]; then
        rlPhaseStartTest "Test nvrTestPackage()"
            test_nvrTestPackage
        rlPhaseEnd
        rlPhaseStartTest "Test nvrComparePackage()"
            test_nvrComparePackage
        rlPhaseEnd
    fi

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
