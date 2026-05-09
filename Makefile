SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_ROOT := $(CURDIR)
ENV_FILE := $(PROJECT_ROOT)/.env
COMPOSE := docker compose --env-file $(ENV_FILE) -f docker-compose.yml

.PHONY: help init check set-target show-target build up down restart llm-up llm-down agent-up agent-down status logs shell health task task-file exec browser clean

help:
	@echo "Available targets:"
	@echo "  make init                                   # create .env and local folders"
	@echo "  make check                                  # verify docker/git/python availability"
	@echo "  make set-target TARGET_REPO=/abs/path       # bind a target repo for the agent"
	@echo "  make show-target                            # print the current target repo"
	@echo "  make build                                  # build the agent image"
	@echo "  make up                                     # start llm + agent services"
	@echo "  make down                                   # stop all services"
	@echo "  make restart                                # restart llm + agent services"
	@echo "  make status                                 # show compose status"
	@echo "  make logs SERVICE=llm                       # tail service logs"
	@echo "  make shell                                  # open a shell inside the agent container"
	@echo "  make health                                 # check the llama OpenAI-compatible endpoint"
	@echo "  make task TASK=\"do X\" [FILES=\"a b\"]      # run one task against the bound repo"
	@echo "  make task-file FILE=tasks/next_task.md      # run one task from a file"
	@echo "  make exec CMD=\"pytest -q\"                  # run any command inside the target repo"
	@echo "  make browser                                # launch aider browser UI inside the container"
	@echo "  make clean                                  # remove local state/log artifacts"

init:
	@test -f .env || cp .env.example .env
	@mkdir -p state logs models  state/agent-home
	@chmod +x bin/agentctl bin/run_task.sh bin/run_command.sh
	@echo "Initialized. Edit .env if needed, then run 'make set-target TARGET_REPO=/abs/path'."

check:
	@command -v docker >/dev/null || (echo "docker not found" && exit 1)
	@docker compose version >/dev/null || (echo "docker compose not available" && exit 1)
	@command -v git >/dev/null || (echo "git not found" && exit 1)
	@command -v python3 >/dev/null || (echo "python3 not found" && exit 1)
	@echo "Prerequisites look good."

set-target:
	@test -n "$(TARGET_REPO)" || (echo "Usage: make set-target TARGET_REPO=/absolute/path/to/repo" && exit 1)
	@python3 bin/update_env.py --file .env --key TARGET_REPO --value "$(TARGET_REPO)"
	@python3 bin/target_info.py --repo "$(TARGET_REPO)"

show-target:
	@python3 bin/show_target.py --file .env

build:
	@$(COMPOSE) build agent

up:
	@$(COMPOSE) up -d llm agent
	@echo "Services are starting. Run 'make health' when the model is ready."

llm-up:
	@$(COMPOSE) up -d llm

agent-up:
	@$(COMPOSE) up -d agent

down:
	@$(COMPOSE) down

llm-down:
	@$(COMPOSE) stop llm

agent-down:
	@$(COMPOSE) stop agent

restart: down up

status:
	@$(COMPOSE) ps

logs:
	@test -n "$(SERVICE)" || (echo "Usage: make logs SERVICE=llm|agent" && exit 1)
	@$(COMPOSE) logs -f $(SERVICE)

shell:
	@$(COMPOSE) exec agent bash

health:
	@$(COMPOSE) exec agent bash -lc 'python /workspace/control/bin/llm_healthcheck.py --base-url "http://llm:$${LLM_PORT}/v1"'

task:
	@test -n "$(TASK)" || (echo "Usage: make task TASK=\"...\" [FILES=\"path1 path2\"]" && exit 1)
	@$(COMPOSE) exec \
		-e TASK="$(TASK)" \
		-e FILES="$(FILES)" \
		-e CONTEXT_ENABLE="$(CONTEXT_ENABLE)" \
		-e CONTEXT_BUDGET="$(CONTEXT_BUDGET)" \
		agent /workspace/control/bin/run_task.sh

task-file:
	@test -n "$(FILE)" || (echo "Usage: make task-file FILE=path/to/task.md [FILES=\"path1 path2\"]" && exit 1)
	@test -f "$(FILE)" || (echo "Task file not found: $(FILE)" && exit 1)
	@$(COMPOSE) exec \
		-e TASK_FILE="/workspace/control/$(FILE)" \
		-e FILES="$(FILES)" \
		-e CONTEXT_ENABLE="$(CONTEXT_ENABLE)" \
		-e CONTEXT_BUDGET="$(CONTEXT_BUDGET)" \
		agent /workspace/control/bin/run_task.sh

exec:
	@test -n "$(CMD)" || (echo "Usage: make exec CMD=\"...\"" && exit 1)
	@$(COMPOSE) exec -e RUN_CMD="$(CMD)" agent /workspace/control/bin/run_command.sh

browser:
	@$(COMPOSE) exec agent bash -lc 'cd /workspace/target && aider --config /workspace/control/.aider.conf.yml --model openai/$${MODEL_ALIAS} --openai-api-base http://llm:$${LLM_PORT}/v1 --openai-api-key "$${OPENAI_API_KEY}" --browser'

clean:
	@rm -rf logs/* state/*
	@echo "Removed local logs and state artifacts."
