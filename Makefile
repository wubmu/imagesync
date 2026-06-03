.PHONY: all debug

all:
	git add .
	git commit -m "update"
	git push

debug:
	export ACTIONS_RUNNER_DEBUG=true
	export ACTIONS_STEP_DEBUG=true
	bin/act -W .github/workflows/image-mirror-schedule.yaml push
	bash script.sh
