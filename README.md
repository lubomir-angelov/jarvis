# OpenHands controller repo

```bash
~/repos/jarvis/
├── Makefile
├── launcher.py
├── requirements.txt
├── models/
│   └── hotswap/
│       └── Qwen3.8-27B-UD-Q4_K_XL.gguf
└── projects/
```


# Initial setup

Assuming the repo already exists:

```bash
cd ~/repos/jarvis

mkdir -p models/hotswap
mkdir -p projects
```

Put the GGUF there:

```bash
~/repos/jarvis/models/hotswap/
└── Qwen3.8-27B-UD-Q4_K_XL.gguf
```

Verify:

```bash
make local-models
```

Then:

```bash
make bootstrap
```

bootstrap only pulls the llama.cpp and OpenHands container images, not model weights.

Start:

```bash
make llm-up
```

Watch startup:

```bash
make llm-logs
```

Then:

```bash
make llm-wait
```

And see exactly what model ID llama.cpp assigned:

```bash
make models
```

or just:

```bash
make model-id
```

The model ID matters because llama.cpp router mode selects the model from the "model" property of each request, and autoload is enabled by default/currently supported explicitly.

You do not need to manually copy that ID for the common case: make smoke, make tool-smoke, and make agent automatically take the first ID returned by /v1/models.

So:

```bash
make smoke
```

then:

```bash
make tool-smoke
```

and finally:

```bash
make project NAME=test-agent


make agent \
    PROJECT=./projects/test-agent \
    TASK='Create a Python package with a CLI that prints Hello World. Add pytest tests and run them.'
```