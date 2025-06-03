.PHONY: install start stop restart status logs update clean help

# Default target
help:
	@echo "UrBackup Docker Installation"
	@echo "Available commands:"
	@echo "  install  - Run installation script"
	@echo "  start    - Start UrBackup server"
	@echo "  stop     - Stop UrBackup server"
	@echo "  restart  - Restart UrBackup server"
	@echo "  status   - Show server status"
	@echo "  logs     - Show server logs"
	@echo "  update   - Update server"
	@echo "  clean    - Clean installation"

install:
	@chmod +x install.sh
	@./install.sh

start:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh start; else echo "Run 'make install' first"; fi

stop:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh stop; else echo "Run 'make install' first"; fi

restart:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh restart; else echo "Run 'make install' first"; fi

status:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh status; else echo "Run 'make install' first"; fi

logs:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh logs; else echo "Run 'make install' first"; fi

update:
	@if [ -f urbackup-control.sh ]; then ./urbackup-control.sh update; else echo "Run 'make install' first"; fi

clean:
	@echo "This will remove all UrBackup data. Are you sure? (y/N)"
	@read -r response; if [ "$$response" = "y" ] || [ "$$response" = "Y" ]; then \
		if [ -f urbackup-control.sh ]; then ./urbackup-control.sh stop; fi; \
		sudo systemctl disable urbackup-docker.service 2>/dev/null || true; \
		sudo rm -f /etc/systemd/system/urbackup-docker.service; \
		sudo systemctl daemon-reload; \
		docker-compose down --rmi all 2>/dev/null || true; \
		rm -rf urbackup/ docker-compose.yml urbackup-control.sh; \
		echo "UrBackup installation cleaned"; \
	fi
