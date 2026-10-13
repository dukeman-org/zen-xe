# Wrapper used by dkms.conf (MAKE[0]); also handy by hand:
#   make KVER=7.2.9-arch1-1            (KDIR defaults to /lib/modules/$(KVER)/build)
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
all:
	bash ./build.sh "$(KVER)" "$(KDIR)"
clean:
	rm -rf src ktree
.PHONY: all clean
