# Shared Folder — fma-llm

This folder is the shared filesystem between your host machine, the Ghidra MCP container, and the open-terminal container. Drop binaries here for analysis, place Ghidra projects here, and all three environments see the same files.

## Mount Layout

| Environment | Shared folder path | Projects path |
|---|---|---|
| **Your host** | `./shared/` (or your `SHARED_FOLDER` value) | `./shared/projects/` |
| **ghidra-mcp-headless** | `/tmp/` | `/projects/` |
| **open-terminal** | `/home/user/shared/` | `/home/user/projects/` |

All paths above point to the same underlying files. A file created in one environment is immediately visible in the others.

## What Goes Where

- **Binaries for analysis** → the shared folder root. The model will reference them as `/tmp/my-binary.exe` (Ghidra context) or `/home/user/shared/my-binary.exe` (terminal context).
- **Ghidra projects** → the `projects/` subdirectory. The model references these as `/projects/my-project/` in Ghidra context. This folder is created automatically when Ghidra saves a new project.

## Usage Prompts

### For AI Agents

When a user asks you to analyze a binary, the file paths depend on which tool server you're using:

| Tool server | Path to use | Example prompt |
|---|---|---|
| Ghidra MCP tools | `/tmp/<filename>` | `Import /tmp/my-binary.exe and decompile main` |
| open-terminal tools | `/home/user/shared/<filename>` | `Run file /home/user/shared/my-binary.exe` |

Both paths refer to the same host file. Use Ghidra for decompilation, cross-references, and structured analysis. Use the terminal for shell commands, `strings`, `gdb`, `objdump`, and scripting.

### Example Workflow

```
Host:     scp suspected-malware.exe ./shared/
Agent:    Import /tmp/suspected-malware.exe into Ghidra, decompile main,
          then run `strings /home/user/shared/suspected-malware.exe` and
          report anything suspicious.
```

### Notes

- The `projects/` subdirectory is optional on disk — Ghidra creates it on first project save.
- If you delete this folder, Ghidra projects inside are gone.
- open-terminal runs as user `user` with home at `/home/user/`.
