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
	# Units reference /usr/bin/tmuxsaver; rewrite to the installed binary.
	for unit in tmuxsaver-save.service tmuxsaver-restore.service; do \
	    mkdir -p $(DESTDIR)$(PREFIX)/lib/systemd/user && \
	    sed 's|/usr/bin/tmuxsaver|$(PREFIX)/bin/tmuxsaver|g' systemd/$$unit \
	        > $(DESTDIR)$(PREFIX)/lib/systemd/user/$$unit && \
	    chmod 644 $(DESTDIR)$(PREFIX)/lib/systemd/user/$$unit || exit 1; \
	done

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

# ── Version bump ────────────────────────────────────────────────────────────
# Usage: make bump V=0.4.16 — updates the script, the package control file and
# the README's install commands. Merging the bump to main cuts the release.

.PHONY: bump
bump:
	@[ -n "$(V)" ] || { echo "usage: make bump V=x.y.z"; exit 1; }
	sed -i 's/^TMUXSAVER_VERSION=".*"/TMUXSAVER_VERSION="$(V)"/' tmuxsaver
	sed -i 's/^Version:.*/Version: $(V)/' packaging/DEBIAN/control
	sed -i 's/$(subst .,\.,$(VERSION))/$(V)/g' README.md
	@echo "Bumped $(VERSION) -> $(V)"

.PHONY: check
check:
	bash -n tmuxsaver
	bash -n install.sh
	bash -n packaging/DEBIAN/postinst
	bash -n packaging/DEBIAN/prerm
	bash -n tests/integration.sh
	@echo "Syntax OK"

# ── Lint / tests (also run by CI on every PR) ───────────────────────────────

.PHONY: lint
lint:
	shellcheck tmuxsaver install.sh packaging/DEBIAN/postinst packaging/DEBIAN/prerm tests/integration.sh
	shellcheck -s bash shell/tmuxsaver.sh
	@echo "shellcheck OK"

# Creates and deletes a throwaway user: run it in CI, a container or a VM.
.PHONY: test
test:
	sudo tests/integration.sh
