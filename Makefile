SHELL      = /bin/bash
GIT        = https://github.com/RetroPie/RetroPie-Setup.git
GITDIR     = $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

FROM       = ubuntu:18.04
MAINTAINER = joffr3y
NAME       = retropie
TAG        = 4.4
IMG        = $(MAINTAINER)/$(NAME):$(TAG)
TZ         = Europe/Paris
USER       = retropie
HOME       = /home/$(USER)
UID        = $(shell id -u)
AUDIO_GID  = $(shell grep audio /etc/group | cut -d: -f3)
VIDEO_GID  = $(shell grep video /etc/group | cut -d: -f3)
INPUT_GID  = $(shell grep input /etc/group | cut -d: -f3)
CMD        = emulationstation

SED        = sed
TEMPLATES  = Dockerfile docker-compose.yml


all: $(TEMPLATES) image

$(TEMPLATES):
	@$(SED) \
	    -e "s|@GITDIR@|$(GITDIR)|g" \
	    -e "s|@FROM@|$(FROM)|g" \
	    -e "s|@MAINTAINER@|$(MAINTAINER)|g" \
	    -e "s|@IMG@|$(IMG)|g" \
	    -e "s|@TZ@|$(TZ)|g" \
	    -e "s|@USER@|$(USER)|g" \
	    -e "s|@UID@|$(UID)|g" \
	    -e "s|@HOME@|$(HOME)|g" \
	    -e "s|@AUDIO_GID@|$(AUDIO_GID)|g" \
	    -e "s|@VIDEO_GID@|$(VIDEO_GID)|g" \
	    -e "s|@INPUT_GID@|$(INPUT_GID)|g" \
	    -e "s|@CMD@|$(CMD)|g" \
	    ./templates/$@.in > $@

# Build image with all dependencies
image:
	@docker build . -t $(IMG)

# Get and patch setup scripts
get-setup-scripts:
	@[[ -d ./opt ]] || mkdir -vp ./opt
	@if [[ -d ./opt/scripts ]]; then \
	    echo 'Update RetroPie-Setup...' ;\
	    cd ./opt/scripts || exit 1 ;\
	    git pull ;\
	else \
	    cd ./opt || exit 1 ;\
	    git clone --depth=1 $(GIT) scripts ;\
	fi
	@printf 'Remove all su/sudo call... '
	@find ./opt/scripts -name "*.sh" -type f -exec \
	    $(SED) \
	        -e 's|"$$(id -u)" -ne 0|0 -ne 0|g' \
	     -E -e 's/(sudo|su)(\s"?\$$user"?|\s-{1,2}[[:alpha:]]+){0,2}\s//g' \
	        -i {} \;
	@printf 'Done\n'

# Build retropie with docker
retropie: get-setup-scripts
	@[[ -d ./datas ]] || mkdir -v ./datas
	@docker run --rm -it \
	    --user root \
	    --device /dev/input \
	    -v $(GITDIR)/opt:/opt \
	    -v $(GITDIR)/datas:$(HOME) \
	    -v $(GITDIR)/datas/emulationstation:/etc/emulationstation \
	    $(IMG) /opt/scripts/retropie_packages.sh setup basic_install
	sudo chown -R $(UID):$(UID) $(GITDIR)/opt $(GITDIR)/datas

# Test if all shared libraries are installed
check-deps:
	@docker-compose run --rm retropie bash -c \
	"LC_ALL=C find /opt/retropie -type f -perm /u+x -exec ldd {} \; | grep 'not found'" \
	|| echo 'Dependencies OK'

# Enjoy!
run:
	@docker-compose run --rm retropie emulationstation

# Clean
clean:
	@rm -f ./Dockerfile ./docker-compose.yml

# Show this help prompt
help:
	@echo '  Usage:'
	@echo '    make <target>'
	@echo
	@echo '  Targets:'
	@awk '/^#/{ comment = substr($$0,3) } comment && /^[a-zA-Z][a-zA-Z0-9_-]+ ?:/{ print "   ", $$1, comment }' $(MAKEFILE_LIST) | column -t -s ':'

.PHONY: all image get-setup-scripts retropie check-deps run clean help
