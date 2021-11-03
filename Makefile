.PHONY: help clean clean-all clean-assets upgrade-dev-deps upgrade-deps dev build test code	\
	devinfra deploy release deploy-prod

pkg := textio-pynamodb
codedir := $(shell echo $(pkg) | sed 's/-/_/'g)
testdir := tests

syspython := python3

python := venv/bin/python
pip := venv/bin/pip-s3
aws := venv/bin/aws

codefiles := $(shell find $(codedir) -name '*' -not \( -path '*__pycache__*' \))
testfiles := $(shell find $(testdir) -name '*' -not \( -path '*__pycache__*' \))

devinfra-cf := devinfra.yml
devinfra-name := $(pkg)-devinfra
devinfra-circleci-user := bot-circleci-pynamodb

# Dev environment
assume-role ?= textioaws assumerole --config $(config)

# cite: https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
# automatically documents the makefile, by outputing everything behind a ##
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:  ## Clean build artifacts but NOT downloaded assets
	# Python build
	find $ . -name '__pycache__' -exec rm -Rf {} +
	find $ . -name '*.py[co]' -delete
	rm -rf build
	rm -rf dist
	rm -rf *.egg-info
	rm -rf *.egg
	rm -rf *.eggs
	rm -rf *.whl
	rm -rf $(pkg)-*

	# Textio build
	rm -rf venv*
	rm -f pips3-master.tar.gz
	rm -f .venv
	rm -f .dev
	rm -f .assets
	rm -f .build
	rm -f .test
	rm -f .code
	rm -f .devinfra
	rm -f .mypy
	rm -rf .mypy_cache

	# Test
	rm -rf .cache/
	rm -f pytest-out.xml
	rm -rf .pytest_cache/

clean-all: clean  ## Clean everything

venv:
	$(syspython) -m venv venv

.venv: venv
	venv/bin/pip install --upgrade pip wheel setuptools --disable-pip-version-check
	venv/bin/pip install --progress-bar off "awscli~=1.0"
	$(aws) s3 cp s3://textio-pypi-us-west-2/pypi/0/dev/pips3/pips3-master.tar.gz .
	venv/bin/pip install --progress-bar off pips3-master.tar.gz
	$(pip) install --upgrade pips3
	touch .venv

pips3-master.tar.gz:
	rm -f .venv
	$(MAKE) .venv  # pips3-master.tar.gz downloaded as a side-effect

%_frozen.txt: %.txt
	$(MAKE) .venv
	$(syspython) -m venv "venv-$@"
	venv-$@/bin/pip install --upgrade pip wheel setuptools --disable-pip-version-check
	$(pip) --pip="venv-$@/bin/pip" install pips3 --disable-pip-version-check
	. "venv-$@/bin/activate" && \
		if [ -e "$@" ]; then pip-s3 install -r "$@"; fi && \
		pip-s3 install -r "$<" && \
		if [ -e "$@" ]; then chmod 644 "$@"; fi && \
		echo '# DO NOT EDIT, use Makefile' > "$@" && \
		pip freeze -l >> "$@" && \
		sed -E -i'.bak' -e 's/scikit-learn([^[])/scikit-learn[alldeps]\1/' "$@" && \
		rm -f "$@.bak" && \
		chmod 444 "$@"
	rm -rf "venv-$@"

requirements_frozen.txt: setup.py
	$(MAKE) .venv
	$(syspython) -m venv "venv-$@"
	venv-$@/bin/pip install --upgrade pip wheel setuptools --disable-pip-version-check
	$(pip) --pip="venv-$@/bin/pip" install pips3 --disable-pip-version-check
	. "venv-$@/bin/activate" && \
		if [ -e "$@" ]; then pip-s3 install -r "$@"; fi && \
		pip-s3 install -e . && \
		if [ -e "$@" ]; then chmod 644 "$@"; fi && \
		echo '# DO NOT EDIT, use Makefile' > "$@" && \
		pip freeze -l | grep -v $(pkg) >> "$@" && \
		sed -E -i'.bak' -e 's/scikit-learn([^[])/scikit-learn[alldeps]\1/' "$@" && \
		rm -f "$@.bak" && \
		chmod 444 "$@"
	rm -rf "venv-$@"

upgrade-dev-deps:  ## Upgrade the dev-time dependencies
	rm -f requirements_dev_frozen.txt
	$(MAKE) clean
	$(MAKE) requirements_dev_frozen.txt

upgrade-deps:  ## Upgrade the run-time dependencies
	rm -f requirements_frozen.txt
	$(MAKE) clean
	$(MAKE) requirements_frozen.txt

.dev: .venv requirements_dev_frozen.txt
	$(pip) install --progress-bar off -r requirements_dev_frozen.txt
	touch .dev

.build: .dev $(codefiles) requirements_frozen.txt
	$(pip) install --progress-bar off -r requirements_frozen.txt
	$(pip) install --progress-bar off -e .
	touch .build

# Arguments for pytest, e.g. "make test t='-k MyTest'"
t ?=
.test: .dev .build $(testfiles)
	venv/bin/py.test $(testdir) $(t) -vv --failed-first \
		--junit-xml=pytest-out.xml; \
		rc="$$?"; \
		if [ "$$rc" -eq 5 ]; then echo "No tests in './$(testdir)', skipping"; \
		elif [ "$$rc" -ne 0 ]; then exit "$$rc"; \
		fi
	touch .test

check ?=
.code: .dev .build .test
	touch .code

# the circle users are always deployed with the "main/dev" config
.devinfra: config="main/dev" # this sets the value of this variable for all following targets with the same name
.devinfra:
	$(MAKE) .dev
	$(assume-role) \
		venv/bin/runcf -n '$(devinfra-name)' -i -f \
			-p "CircleCiUserName=$(devinfra-circleci-user)" \
			$(devinfra-cf)
	touch .devinfra

dev: .dev  ## Setup the local dev environment

build: .build  ## Build into local environment (for use in REPL, etc.)

test: .test  ## Run unit tests

code: .code  ## Build code, and run all checks (tests, pep8, manifest check, etc.)

devinfra: .devinfra  ## Setup the remote (AWS) development infrastructure.  Run once manually.

deploy: .dev .code  ## Upload to private PyPI under the branch.  Normally called by CircleCI
	. venv/bin/activate && deploy.sh ./setup.py dev

# Custom release message, e.g. "make release msg='jobtype model'"
msg ?=
release: .dev .code  ## Release a new prod version: add a tag and Circle builds and uploads. Add a release message with: "make release msg='My release message'"
	. venv/bin/activate && release.sh ./setup.py "$(msg)"

deploy-prod: .dev .code  ## EMERGENCY USE ONLY. Upload to private PyPI under the version number. Normally called by CircleCI
	. venv/bin/activate && deploy.sh ./setup.py prod
