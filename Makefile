SHELL := /bin/bash

.PHONY: build help install-ontop

help:
	@echo "Available commands:"
	@echo "  make build    - Build the project"
	@echo ""
	@echo "Set alias ontop='' or install Java package from ontop."

install-ontop:
 	@pushd $${HOME}/bin &&
		rm -rf $${HOME}/bin/ontop* && \
		ontop_version=5.3.0 && \
		wget https://github.com/ontop/ontop/releases/download/ontop-$${ontop_version}/ontop-cli-$${ontop_version}.zip && \
		mkdir ontop-cli-$${ontop_version} && \
		unzip ontop-cli-$${ontop_version}.zip && \
 	unzip ontop-cli-5.3.0.zip 
 	unzip -l ontop-cli-5.3.0.zip 
 	rm ontop ontop-completion.sh 
 	unzip -l ontop-cli-5.3.0.zip 
 	unzip -l ontop-cli-5.3.0.zip 
 	rm ontop.bat 
 	mkdir ontop
 	cd ontop/
 	unzip ../ontop-cli-5.3.0.zip 
 	mv ontop ontop-cli-5.3.0
 	ln -s ontop-cli-5.3.0/ontop ontop