#!/bin/sh
# Another big fat ugly hack ...
# Rationale: we don't want to change too much on Gluons core files,
# but we need to replace some for practical reasons. Thus we clone
# the original, stash them in the firmware as -ffgt versions and
# on first boot replace the Gluon ones with their FFGT counterparts.
# Yes, what we would need is some kind of overlay packages that may
# replace existig files during image creation.
#
# Hmm, looks like it's possible to have Gluon apply patches to itself?
# Anyone willing to explain that magic to me? -- wusel, 2018-07-19 FIXME!

START=1

if [ -e /etc/init.d/gluon-respondd-ffgt ]; then
  mv /etc/init.d/gluon-respondd-ffgt /etc/init.d/gluon-respondd
fi
