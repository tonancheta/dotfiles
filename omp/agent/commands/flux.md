---
description: Generate an image with FLUX.1 (NVIDIA Build) and save it to the current directory
---
Generate an image with FLUX.1 on NVIDIA Build for the request below.

Run this, quoting the prompt text as a single argument and forwarding any flags I
included (--width, --height, --steps, --cfg-scale, --seed, --model, --out):

    python3 "$HOME/.omp/agent/scripts/flux.py" "<PROMPT>" [flags]

Then report the saved image's absolute path and the seed it printed. If the script
errors about a missing NVIDIA_API_KEY, tell me to set it in the shell env or
~/.omp/agent/.env rather than retrying.

Request: $ARGUMENTS
