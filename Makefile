# kwin-focus — install / upgrade / remove the CLI tool and the Plasma 6 applet.
#
#   make install        link the CLI onto $PATH and install the applet
#   make install-cli    only the CLI symlink (~/bin/kwin-focus)
#   make install-applet only the Plasma applet (install or upgrade)
#   make upgrade         re-deploy the applet after editing it
#   make uninstall       remove both
#   make dev             run the applet standalone (plasmawindowed) for testing

APPLET_ID  := org.dicosmo.windowfilter
APPLET_SRC := applet
BINDIR     ?= $(HOME)/bin
KPACKAGE   := kpackagetool6

.PHONY: all install install-cli install-applet upgrade uninstall dev

all:
	@echo "targets: install  install-cli  install-applet  upgrade  uninstall  dev"

install: install-cli install-applet

install-cli:
	@mkdir -p $(BINDIR)
	ln -sf $(CURDIR)/cli/kwin-focus $(BINDIR)/kwin-focus
	@echo "linked $(BINDIR)/kwin-focus -> $(CURDIR)/cli/kwin-focus"

install-applet:
	@if $(KPACKAGE) --type Plasma/Applet --list 2>/dev/null | grep -qx $(APPLET_ID); then \
		$(KPACKAGE) --type Plasma/Applet --upgrade $(APPLET_SRC); \
	else \
		$(KPACKAGE) --type Plasma/Applet --install $(APPLET_SRC); \
	fi

upgrade:
	$(KPACKAGE) --type Plasma/Applet --upgrade $(APPLET_SRC)

uninstall:
	-$(KPACKAGE) --type Plasma/Applet --remove $(APPLET_ID)
	-rm -f $(BINDIR)/kwin-focus

dev:
	plasmawindowed $(APPLET_ID)
