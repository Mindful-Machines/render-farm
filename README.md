# Seed

Starter [APM](https://github.com/microsoft/apm) project — a baseline set of agent skills, agents, and MCP servers to drop into a new repo.

## Setup

```sh
apm install
apm compile
```

This generates `.claude/` and `.mcp.json` (both gitignored) from `apm.yml`.

Requires `FIRECRAWL_API_KEY` in the environment for the Firecrawl MCP server.
