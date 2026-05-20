SHELL := /bin/bash
.PHONY: help install add remove reset uninstall menu test lint

help:
	@echo "wireguard_vds — Makefile targets"
	@echo
	@echo "  make install                  полная свежая установка"
	@echo "  make add EMAIL=user@x.com     добавить клиента"
	@echo "  make remove EMAIL=user@x.com  удалить клиента"
	@echo "  make reset                    сбросить настройки"
	@echo "  make uninstall                снести wireguard"
	@echo "  make menu                     интерактивное меню"
	@echo
	@echo "  make test                     прогнать smoke tests"
	@echo "  make lint                     прогнать shellcheck"

install:   ; ./wgctl install
add:       ; ./wgctl add "$(EMAIL)"
remove:    ; ./wgctl remove "$(EMAIL)"
reset:     ; ./wgctl reset
uninstall: ; ./wgctl uninstall
menu:      ; ./wgctl menu

test:      ; ./tests/smoke.sh
lint:      ; shellcheck -S style scripts/*.sh tests/*.sh wgctl
