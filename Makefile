SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

# ======================================================================
# Jarvis
# ======================================================================

REPO_ROOT := $(HOME)/repos/jarvis

MODELS_DIR := $(REPO_ROOT)/models/hotswap
PROJECTS_DIR := $(REPO_ROOT)/projects

# ======================================================================
# Python / OpenHands
# ======================================================================

PYTHON ?= python3.12

VENV := $(REPO_ROOT)/.venv
PY := $(VENV)/bin/python
PIP := $(VENV)/bin/pip

OPENHANDS_SERVER_IMAGE ?= ghcr.io/openhands/agent-server:latest-python

# ======================================================================
# Docker
# ======================================================================

NETWORK ?= jarvis-net

# ======================================================================
# llama.cpp
# ======================================================================

LLM_CONTAINER ?= jarvis-llm

# Official upstream llama.cpp CUDA image.
#
# If your driver/toolkit setup is CUDA 13 capable, you can override:
#
#   make llm-up \
#       LLM_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda13
#
LLM_IMAGE ?= ghcr.io/ggml-org/llama.cpp:server-cuda

LLM_HOST_PORT ?= 8000
LLM_CONTAINER_PORT ?= 8080

# ======================================================================
# Model runtime
# ======================================================================

# Router mode:
#
# Every GGUF found under models/hotswap becomes available through
# GET /v1/models.
#
# If more than one model exists, select one when running the agent:
#
#   make agent \
#       MODEL_ID='Qwen3.8-27B-UD-Q4_K_XL.gguf' \
#       PROJECT=... \
#       TASK='...'
#
# If MODEL_ID is omitted, the launcher target uses the first model
# returned by /v1/models.

MODEL_ID ?=

MODELS_MAX ?= 1

# ======================================================================
# llama.cpp runtime configuration
# ======================================================================

CTX_SIZE ?= 262144

BATCH_SIZE ?= 2048
UBATCH_SIZE ?= 512

PARALLEL ?= 1

CACHE_REUSE ?= 256
CACHE_RAM ?= 20000

CACHE_TYPE_K ?= q4_0
CACHE_TYPE_V ?= q4_0

SPEC_TYPE ?= draft-mtp
SPEC_DRAFT_N_MAX ?= 3

TEMP ?= 1.0
TOP_P ?= 0.95
TOP_K ?= 20
MIN_P ?= 0.0

REPEAT_PENALTY ?= 1.0
PRESENCE_PENALTY ?= 0.0

# ======================================================================
# Targets
# ======================================================================

.PHONY: \
	help \
	check \
	dirs \
	install \
	network \
	pull-images \
	bootstrap \
	local-models \
	llm-up \
	llm-down \
	llm-restart \
	llm-wait \
	llm-status \
	llm-logs \
	models \
	model-id \
	smoke \
	tool-smoke \
	project \
	agent \
	clean

# ======================================================================
# Help
# ======================================================================

help:
	@echo
	@echo "Jarvis local coding/research agent"
	@echo
	@echo "Repository:"
	@echo "  $(REPO_ROOT)"
	@echo
	@echo "Initial setup:"
	@echo "  make bootstrap"
	@echo
	@echo "Models:"
	@echo "  make local-models"
	@echo "  make models"
	@echo
	@echo "LLM:"
	@echo "  make llm-up"
	@echo "  make llm-wait"
	@echo "  make llm-status"
	@echo "  make llm-logs"
	@echo "  make llm-restart"
	@echo "  make llm-down"
	@echo
	@echo "Testing:"
	@echo "  make smoke"
	@echo "  make tool-smoke"
	@echo
	@echo "Projects:"
	@echo "  make project NAME=test-agent"
	@echo
	@echo "Agent:"
	@echo "  make agent PROJECT=./projects/test-agent TASK='Create a Python CLI'"
	@echo
	@echo "Explicit model:"
	@echo "  make agent MODEL_ID='<id from make models>' PROJECT=... TASK='...'"
	@echo

# ======================================================================
# Environment checks
# ======================================================================

check:
	@command -v docker >/dev/null || \
		(echo "ERROR: docker is not installed"; exit 1)

	@docker info >/dev/null 2>&1 || \
		(echo "ERROR: Docker daemon is not running"; exit 1)

	@command -v $(PYTHON) >/dev/null || \
		(echo "ERROR: $(PYTHON) is not installed"; exit 1)

	@command -v curl >/dev/null || \
		(echo "ERROR: curl is not installed"; exit 1)

	@echo "Docker : OK"
	@echo "Python : $$($(PYTHON) --version)"
	@echo "curl   : OK"

	@if command -v nvidia-smi >/dev/null; then \
		echo; \
		echo "NVIDIA GPU:"; \
		nvidia-smi \
			--query-gpu=name,memory.total,driver_version \
			--format=csv,noheader; \
	else \
		echo "WARNING: nvidia-smi not found"; \
	fi

# ======================================================================
# Directories
# ======================================================================

dirs:
	@mkdir -p "$(MODELS_DIR)"
	@mkdir -p "$(PROJECTS_DIR)"

	@echo "Models:"
	@echo "  $(MODELS_DIR)"
	@echo
	@echo "Projects:"
	@echo "  $(PROJECTS_DIR)"

# ======================================================================
# Python environment
# ======================================================================

install:
	@test -d "$(VENV)" || \
		$(PYTHON) -m venv "$(VENV)"

	@$(PIP) install --upgrade pip
	@$(PIP) install -r "$(REPO_ROOT)/requirements.txt"

# ======================================================================
# Docker network
# ======================================================================

network:
	@docker network inspect "$(NETWORK)" >/dev/null 2>&1 || \
		docker network create "$(NETWORK)" >/dev/null

	@echo "Docker network: $(NETWORK)"

# ======================================================================
# Docker images
#
# This downloads container images ONLY.
# It never downloads a model.
# ======================================================================

pull-images:
	docker pull "$(LLM_IMAGE)"
	docker pull "$(OPENHANDS_SERVER_IMAGE)"

# ======================================================================
# Bootstrap
# ======================================================================

bootstrap: check dirs install network pull-images
	@echo
	@echo "Bootstrap complete."
	@echo
	@echo "Place your GGUF model under:"
	@echo
	@echo "  $(MODELS_DIR)"
	@echo
	@echo "Then run:"
	@echo
	@echo "  make local-models"
	@echo "  make llm-up"
	@echo "  make llm-wait"
	@echo "  make models"
	@echo "  make tool-smoke"
	@echo

# ======================================================================
# Local model inspection
# ======================================================================

local-models:
	@echo
	@echo "Local model directory:"
	@echo "  $(MODELS_DIR)"
	@echo

	@if ! find "$(MODELS_DIR)" \
		-type f \
		-name '*.gguf' \
		-print \
		-quit \
		| grep -q .; then \
		echo "ERROR: no GGUF files found."; \
		echo; \
		echo "Place the model under:"; \
		echo "  $(MODELS_DIR)"; \
		exit 1; \
	fi

	@find "$(MODELS_DIR)" \
		-type f \
		-name '*.gguf' \
		-printf '%P\n' \
		| sort

# ======================================================================
# llama.cpp
# ======================================================================

llm-up: network local-models
	@docker rm -f "$(LLM_CONTAINER)" >/dev/null 2>&1 || true

	docker run -d \
		--name "$(LLM_CONTAINER)" \
		--network "$(NETWORK)" \
		--gpus all \
		--restart unless-stopped \
		-p 127.0.0.1:$(LLM_HOST_PORT):$(LLM_CONTAINER_PORT) \
		-v "$(MODELS_DIR):/models:ro" \
		--cap-add IPC_LOCK \
		--ulimit memlock=-1:-1 \
		--memory 64g \
		-e LLAMA_LOG_LEVEL=info \
		"$(LLM_IMAGE)" \
		--host 0.0.0.0 \
		--port "$(LLM_CONTAINER_PORT)" \
		--models-dir /models \
		--models-max "$(MODELS_MAX)" \
		--models-autoload \
		--n-gpu-layers -1 \
		--mlock \
		--no-mmap \
		--spec-type "$(SPEC_TYPE)" \
		--spec-draft-n-max "$(SPEC_DRAFT_N_MAX)" \
		--ctx-size "$(CTX_SIZE)" \
		--chat-template-kwargs '{"enable_thinking":true}' \
		--batch-size "$(BATCH_SIZE)" \
		--ubatch-size "$(UBATCH_SIZE)" \
		-np "$(PARALLEL)" \
		--cache-reuse "$(CACHE_REUSE)" \
		--cache-ram "$(CACHE_RAM)" \
		--cache-type-k "$(CACHE_TYPE_K)" \
		--cache-type-v "$(CACHE_TYPE_V)" \
		--flash-attn on \
		--jinja \
		--temp "$(TEMP)" \
		--top-p "$(TOP_P)" \
		--top-k "$(TOP_K)" \
		--min-p "$(MIN_P)" \
		--repeat-penalty "$(REPEAT_PENALTY)" \
		--presence-penalty "$(PRESENCE_PENALTY)"

	@echo
	@echo "llama.cpp router started."
	@echo
	@echo "Container:"
	@echo "  $(LLM_CONTAINER)"
	@echo
	@echo "Models:"
	@echo "  $(MODELS_DIR) -> /models"
	@echo
	@echo "API:"
	@echo "  http://127.0.0.1:$(LLM_HOST_PORT)/v1"
	@echo
	@echo "Next:"
	@echo "  make llm-logs"
	@echo "  make llm-wait"

llm-down:
	@docker rm -f "$(LLM_CONTAINER)" >/dev/null 2>&1 || true

llm-restart: llm-down llm-up

# ======================================================================
# Readiness
# ======================================================================

llm-wait:
	@if ! docker inspect "$(LLM_CONTAINER)" >/dev/null 2>&1; then \
		echo "ERROR: $(LLM_CONTAINER) does not exist."; \
		echo "Run:"; \
		echo "  make llm-up"; \
		exit 1; \
	fi

	@echo "Waiting for llama.cpp..."

	@for i in $$(seq 1 600); do \
		if curl -fsS \
			"http://127.0.0.1:$(LLM_HOST_PORT)/v1/models" \
			>/dev/null 2>&1; then \
			echo "llama.cpp is ready."; \
			exit 0; \
		fi; \
		if [ "$$(docker inspect \
			-f '{{.State.Running}}' \
			"$(LLM_CONTAINER)" \
			2>/dev/null)" != "true" ]; then \
			echo "ERROR: llama.cpp stopped."; \
			docker logs --tail 200 "$(LLM_CONTAINER)"; \
			exit 1; \
		fi; \
		sleep 2; \
	done; \
	echo "ERROR: llama.cpp did not become ready."; \
	docker logs --tail 200 "$(LLM_CONTAINER)"; \
	exit 1

# ======================================================================
# Status / logs
# ======================================================================

llm-status:
	@echo
	@docker ps \
		--filter "name=$(LLM_CONTAINER)" \
		--format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

	@echo
	@echo "GPU:"
	@nvidia-smi

llm-logs:
	docker logs -f "$(LLM_CONTAINER)"

# ======================================================================
# Model discovery
# ======================================================================

models: llm-wait
	@curl -fsS \
		"http://127.0.0.1:$(LLM_HOST_PORT)/v1/models" \
		| $(PY) -m json.tool

model-id: llm-wait
	@curl -fsS \
		"http://127.0.0.1:$(LLM_HOST_PORT)/v1/models" \
		| $(PY) -c '\
import json,sys; \
d=json.load(sys.stdin); \
print(d["data"][0]["id"])'

# ======================================================================
# Smoke test
# ======================================================================

smoke: llm-wait
	@set -e; \
	MODEL="$(MODEL_ID)"; \
	if [ -z "$$MODEL" ]; then \
		MODEL="$$(curl -fsS \
			http://127.0.0.1:$(LLM_HOST_PORT)/v1/models \
			| $(PY) -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')"; \
	fi; \
	echo "Using model: $$MODEL"; \
	curl -fsS \
		"http://127.0.0.1:$(LLM_HOST_PORT)/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d "$$($(PY) -c '\
import json,sys; \
model=sys.argv[1]; \
print(json.dumps({ \
    "model": model, \
    "messages": [ \
        {"role":"user","content":"Reply with exactly LOCAL_LLM_OK"} \
    ], \
    "temperature": 0 \
}))' "$$MODEL")" \
		| $(PY) -m json.tool

# ======================================================================
# Tool calling smoke test
#
# This is the important test before involving OpenHands.
# ======================================================================

tool-smoke: llm-wait
	@set -e; \
	MODEL="$(MODEL_ID)"; \
	if [ -z "$$MODEL" ]; then \
		MODEL="$$(curl -fsS \
			http://127.0.0.1:$(LLM_HOST_PORT)/v1/models \
			| $(PY) -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')"; \
	fi; \
	echo "Using model: $$MODEL"; \
	curl -fsS \
		"http://127.0.0.1:$(LLM_HOST_PORT)/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d "$$($(PY) -c '\
import json,sys; \
model=sys.argv[1]; \
print(json.dumps({ \
  "model": model, \
  "messages": [{ \
    "role":"user", \
    "content":"You MUST call the calculator tool to calculate 17 * 23." \
  }], \
  "tools":[{ \
    "type":"function", \
    "function":{ \
      "name":"calculator", \
      "description":"Evaluate a mathematical expression.", \
      "parameters":{ \
        "type":"object", \
        "properties":{ \
          "expression":{"type":"string"} \
        }, \
        "required":["expression"] \
      } \
    } \
  }], \
  "tool_choice":"auto", \
  "temperature":0 \
}))' "$$MODEL")" \
		| $(PY) -m json.tool

# ======================================================================
# Projects
# ======================================================================

project:
	@test -n "$(NAME)" || \
		(echo "Usage:"; \
		 echo "  make project NAME=my-project"; \
		 exit 1)

	@mkdir -p "$(PROJECTS_DIR)/$(NAME)"

	@if [ ! -d "$(PROJECTS_DIR)/$(NAME)/.git" ]; then \
		git -C "$(PROJECTS_DIR)/$(NAME)" init -b main; \
	fi

	@echo
	@echo "Project created:"
	@echo "  $(PROJECTS_DIR)/$(NAME)"
	@echo
	@echo "Run:"
	@echo "  make agent PROJECT=$(PROJECTS_DIR)/$(NAME) TASK='Your task'"

# ======================================================================
# OpenHands
# ======================================================================

agent: llm-wait
	@test -n "$(PROJECT)" || \
		(echo "ERROR: PROJECT is required"; \
		 echo; \
		 echo "Example:"; \
		 echo "  make agent PROJECT=./projects/demo TASK='Create a Python CLI'"; \
		 exit 1)

	@test -n "$(TASK)" || \
		(echo "ERROR: TASK is required"; exit 1)

	@test -d "$(PROJECT)" || \
		(echo "ERROR: project does not exist: $(PROJECT)"; exit 1)

	@set -e; \
	MODEL="$(MODEL_ID)"; \
	if [ -z "$$MODEL" ]; then \
		MODEL="$$(curl -fsS \
			http://127.0.0.1:$(LLM_HOST_PORT)/v1/models \
			| $(PY) -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')"; \
	fi; \
	echo; \
	echo "Launching OpenHands"; \
	echo "Project : $(abspath $(PROJECT))"; \
	echo "Model   : $$MODEL"; \
	echo "LLM     : http://$(LLM_CONTAINER):$(LLM_CONTAINER_PORT)/v1"; \
	echo; \
	LLM_BASE_URL="http://$(LLM_CONTAINER):$(LLM_CONTAINER_PORT)/v1" \
	LLM_MODEL="openai/$$MODEL" \
	LLM_API_KEY="local" \
	AGENT_DOCKER_NETWORK="$(NETWORK)" \
	OPENHANDS_SERVER_IMAGE="$(OPENHANDS_SERVER_IMAGE)" \
	$(PY) "$(REPO_ROOT)/launcher.py" \
		--project "$(abspath $(PROJECT))" \
		--task "$(TASK)"

# ======================================================================
# Cleanup
# ======================================================================

clean:
	@docker rm -f "$(LLM_CONTAINER)" >/dev/null 2>&1 || true
	@rm -rf "$(VENV)"

	@echo
	@echo "Removed:"
	@echo "  Python virtual environment"
	@echo "  llama.cpp container"
	@echo
	@echo "Preserved:"
	@echo "  $(MODELS_DIR)"
	@echo "  $(PROJECTS_DIR)"