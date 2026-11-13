#!/bin/sh
# Boot hook: AirPlay 2 receiver (nqptp must run before shairport-sync).
DIR=/data/local/capsula-airplay/init.d

case "$1" in
  start)
    "$DIR/nqptp" start
    sleep 2
    "$DIR/shairport-sync" start
    ;;
  stop)
    "$DIR/shairport-sync" stop
    "$DIR/nqptp" stop
    ;;
  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;
esac
exit 0
