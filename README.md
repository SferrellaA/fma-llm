# fma-llm

Quick-install setup for running an llm from an endpoint to use with webui and ghidra-mcp

## Setup:
0. Make sure `docker` and [`uv`](https://docs.astral.sh/uv/) are installed 
1. Run `setup.sh`


## Test Chat:
```bash
uv venv
uv pip install -r requirements.txt
uv run chat.py
```