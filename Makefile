NAME    := tmuxsaver
VERSION := $(shell grep 'TMUXSAVER_VERSION=' tmuxsaver | cut -d'"' -f2)
ARCH    := all
DEB     := $(NAME)_$(VERSION)_$(ARCH).deb

PREFIX  ?= /usr/local
DESTDIR ?=

# ── Install / uninstall ──────────────────────────────────────────────────────

.PHONY: install
install:
	install -Dm 755 tmuxsaver               $(DESTDIR)$(PREFIX)/bin/tmuxsaver
	install -Dm 644 shell/tmuxsaver.sh      $(DESTDIR)$(PREFIX)/share/tmuxsaver/tmuxsaver.sh
	install -Dm 644 systemd/tmuxsaver-save.service \
	                                        $(DESTDIR)$(PREFIX)/lib/systemd/user/tmuxsaver-save.service
	install -Dm 644 systemd/tmuxsaver-restore.service \
	                                        $(DESTDIR)$(PREFIX)/lib/systemd/user/tmuxsaver-restore.service

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/tmuxsaver
	rm -f $(DESTDIR)$(PREFIX)/share/tmuxsaver/tmuxsaver.sh
	rm -f $(DESTDIR)$(PREFIX)/lib/systemd/user/tmuxsaver-save.service
	rm -f $(DESTDIR)$(PREFIX)/lib/systemd/user/tmuxsaver-restore.service

# ── .deb package ────────────────────────────────────────────────────────────

.PHONY: deb
deb: $(DEB)

$(DEB): tmuxsaver shell/tmuxsaver.sh systemd/*.service packaging/DEBIAN/*
	@echo "Building $(DEB) ..."
	# Populate the packaging tree with the current files
	install -Dm 755 tmuxsaver \
	    packaging/usr/bin/tmuxsaver
	install -Dm 644 shell/tmuxsaver.sh \
	    packaging/usr/share/tmuxsaver/tmuxsaver.sh
	install -Dm 644 systemd/tmuxsaver-save.service \
	    packaging/usr/lib/systemd/user/tmuxsaver-save.service
	install -Dm 644 systemd/tmuxsaver-restore.service \
	    packaging/usr/lib/systemd/user/tmuxsaver-restore.service
	# Update the version in the control file
	sed -i "s/^Version:.*/Version: $(VERSION)/" packaging/DEBIAN/control
	chmod 755 packaging/DEBIAN/postinst
	dpkg-deb --build --root-owner-group packaging $(DEB)
	@echo "Built: $(DEB)"

.PHONY: clean
clean:
	rm -f *.deb
	# Remove generated copies inside packaging/ (keep DEBIAN/ meta files)
	rm -rf packaging/usr/

.PHONY: check
check:
	bash -n tmuxsaver
	bash -n install.sh
	@echo "Syntax OK"
