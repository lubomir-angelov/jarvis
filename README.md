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

# Actual Work

```bash
cd ~/repos
git clone git@github.com:your-org/your-project.git
```

Then run:

```bash
cd ~/repos/jarvis


make agent \
    PROJECT=~/repos/your-project \
    TASK='Inspect the repository, understand the architecture, run the existing tests, and summarize the current state. Do not modify anything yet.'
```

Then a coding task:

```bash
make agent \
    PROJECT=~/repos/your-project \
    TASK='Implement the requested feature, add or update tests, run the relevant test suite, and summarize the changes.'
```

The current launcher bind-mounts whatever you pass as PROJECT:

```python
volumes=[
    f"{project}:/workspace",
]
```

so this works equally well for:

```bash
~/repos/jarvis/projects/test-agent
```

or:

```bash
~/repos/my-real-existing-project
```

The agent sees either one simply as:

```bash
/workspace
```

**Important** : the agent container does not need GitHub credentials just to work on a cloned repo. Git authentication remains on the host. So the clean workflow is:

```bash
Host
  git clone / git pull
        ↓
existing repo
        ↓ bind mount
OpenHands
  edit
  test
  inspect git diff
        ↓
Host
  review
  commit
  push
```

Let Jarvis modify the checkout, but keep git push under your control.