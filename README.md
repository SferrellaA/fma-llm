# fma-llm

Quick-install setup for running an llm from an endpoint to use with webui and ghidra-mcp

Based on [this medium piece](https://medium.com/@clearbluejar/supercharging-ghidra-using-local-llms-with-ghidramcp-via-ollama-and-openweb-ui-794cef02ecf7)

## Setup:
0. Make sure `docker`, [`ghidra`](https://github.com/NationalSecurityAgency/ghidra?tab=readme-ov-file#install) and [`uv`](https://docs.astral.sh/uv/) are installed 
1. Add the [GhidraMCP](https://github.com/LaurieWired/GhidraMCP/releases) plugin to Ghidra
    1. Extract the `GhidraMCP-x-y.zip` from the larger .zip
    2. Open Ghidra and go to `File->Install Extensions->➕`
    3. Add the `GhidraMCP-x-y.zip` plugin and restart Ghidra
    4. Open Ghidra's codebrowser window (press the dragon)
        - Ignore the "configure plugin" window that pops up automatically
    5. In codebrowser, go to `File->Configure->Deceloper->Configure`
    6. Make sure the `GhidraMCPPlugin` plugin is checked enabled
2. Install GhidraMCP's requirements
```bash
wget -O ghidramcp.requirements.txt https://raw.githubusercontent.com/LaurieWired/GhidraMCP/refs/heads/main/requirements.txt`
uv venv
uv pip install -r ghidramcp.requirements.txt
uv run bridge_mcp_ghidra.py
```
?. Run `setup.sh`

## Test Chat:
```bash
uv venv
uv pip install -r chat.requirements.txt
uv run chat.py
```