#!/bin/sh
# Only run in a throwaway Alpine container, never on a speaker.
set -eu
[ "${CAPSULA_TEST_CONTAINER:-}" = yes ] || exit 2
mkdir -p /mockbin /dev/snd /etc/init.d
printf 'test-column\n' > /etc/hostname
printf '3.24.1\n' > /etc/alpine-release
printf '# synthetic ALSA config\n' > /etc/asound.conf
printf '#!/bin/sh\necho aarch64\n' > /mockbin/uname
printf '#!/bin/sh\nexit 0\n' > /mockbin/sleep
for tool in apk rc-update rc-service; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >> /tmp/mock-calls\nexit 0\n' "$tool" > "/mockbin/$tool"
done
chmod +x /mockbin/*
export PATH=/mockbin:$PATH
cd /bundle
sh -n install.sh
sh install.sh --check > /tmp/check-output
grep -q PREFLIGHT_PASS /tmp/check-output
[ ! -e /tmp/mock-calls ]
sh install.sh > /tmp/install-output
grep -q INSTALL_PASS /tmp/install-output
grep -q 'name = "test-column";' /etc/shairport-sync.conf
sed -i 's/test-column/Room Custom/' /etc/shairport-sync.conf
sh install.sh > /tmp/repeat-output
grep -q 'name = "Room Custom";' /etc/shairport-sync.conf
sh install.sh --hostname > /tmp/hostname-output
grep -q 'name = "test-column";' /etc/shairport-sync.conf
sh install.sh --name 'Hall & Kitchen|$(false)' > /tmp/custom-output
grep -Fq 'name = "Hall & Kitchen|$(false)";' /etc/shairport-sync.conf
for bad in 'bad"name' 'bad\name' ''; do
    if sh install.sh --name "$bad" >/tmp/bad-output 2>&1; then echo 'Bad name accepted'; exit 1; fi
done
bad=$(printf 'one\ntwo')
if sh install.sh --name "$bad" >/tmp/bad-output 2>&1; then exit 1; fi
printf 'different binary\n' > /usr/local/bin/shairport-sync
if sh install.sh --check >/tmp/bad-output 2>&1; then echo 'Unapproved overwrite accepted'; exit 1; fi
sh install.sh --upgrade > /tmp/upgrade-output
cmp bin/shairport-sync /usr/local/bin/shairport-sync
grep -Fq 'name = "Hall & Kitchen|$(false)";' /etc/shairport-sync.conf
find /root -path '*/files/usr/local/bin/shairport-sync' | grep -q .
printf '3.25.0\n' > /etc/alpine-release
if sh install.sh --check >/tmp/bad-output 2>&1; then echo 'Wrong Alpine accepted'; exit 1; fi
echo INSTALL_TESTS_PASS
