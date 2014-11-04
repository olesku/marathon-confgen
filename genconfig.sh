#!/bin/bash

CONFGEN_SCRIPT="./marathon-confgen.pl"
CONFGEN_OPTS=''
MARATHON_CONFGEN="${CONFGEN_SCRIPT} ${CONFGEN_OPTS}"

OUTFILE="/etc/varnish/marathon-backends.vcl"

reload_varnish() {
	/usr/sbin/service varnish reload
}

log() {
	echo "$(date +'%D %H:%M:%S') - $1"
}

if [ ! -f "${OUTFILE}" ]; then
	log "Config file does not exist yet, creating initial config."
	$MARATHON_CONFGEN > ${OUTFILE}
	reload_varnish
	exit 0;
fi

$MARATHON_CONFGEN > ${OUTFILE}.tmp
grep -q 'backend' ${OUTFILE}.tmp
 
if [ "$?" -eq 1 ]; then
	log "Grep check for backend failed. Not reloading."
	rm -f ${OUTFILE}.tmp
	exit 1;
fi

diff -q ${OUTFILE} ${OUTFILE}.tmp > /dev/null

if [ "$?" -eq 1 ]; then
	mv -f ${OUTFILE}.tmp ${OUTFILE}
	log "Configuration is updated, reloading Varnish."
	reload_varnish
fi

rm -f ${OUTFILE}.tmp
