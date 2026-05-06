# TODO File for AI Processing Later

> Follow the instructions for all superpowers related content (and dependent tasks and precursors) below and then enter planning mode using that skill.  Defer to existing agents and skills if requirements diverge.  That said merge related existing skills and agents that are logically related into the new skills and skill names so that future merges between this project's AI tools and the tools that are being derived from repos update smoothly

## Clone Repositories

### Clone the following repositories using chezmoi

> Adjust chezmoi external default refresh period to 1 month for all external references

* [claude skills](https://github.com/anthropics/skills)
* [superpowers](https://github.com/obra/superpowers)
* [everything-claude-code](https://github.com/affaan-m/everything-claude-code)
* [webmation](https://github.com/appautomaton/webmaton)
* [skills](https://github.com/angular/skills)

## Tool creation

* Add any cli applications added by skills to the default ai instructions list for copilot and claude

## Skill Creation

> Revise any path references to the default ~/.claude and ~/.copilot directories to the env vars that are established in this project
> Move .github skills into the new project tools directory and deploy into the <AGENT_HOME> directory

* Ingest the skills docx, claude-api, pdf, pptx, xlsx from the claude skill repository and wire them into this project's AI tools
* Ingest the writing-plans, writing-skills skill from `superpowers` repo
* Ingest bun-runtime, golang-patterns, golang-testing, github-ops, jira-integration, repo-scan, python-patterns, python-testing, springboot-patterns, springboot-security, springboot-tdd, springboot-verification, git-workflow, security-review, security-scan,
  * For Golang, defer to [project-layout](https://github.com/golang-standards/project-layout) and [go-sea](https://github.com/borland502/go-sea) for project layout
* Ingest any support skills for named skills from those repo sites
* Ingest all skills for webmation
* Ingest all skills for angular
* Create a reconciliation skill for this project that helps injest and merge these external repository skills into the plugin and AI tools managed by this repository.  Prompt if there is a logical change that would be ignored if deferring to this repository's AI tools
* Create a chezmoi skill based on cache usage and [reference](https://www.chezmoi.io/reference/) and [user](https://www.chezmoi.io/user-guide/command-overview/) pages converted from html to markdown
* Create a skill page for any cli tool listed in the default agent instructions with a fair amount of complexity (jq, dasel, rg, fd, etc) convert help pages (if available) to markdown and appropriate skill language.  Fallback to cli help invocations for this information if html reference pages cannot be found.
* Credit all skill repositories in the README.md file

## Refactor project

* Refactor this project's AI tools (skills, agents, etc) to use the layout of the `superpowers` site into a logically named top level folder
* Refactor this project's AI tools to be installed as either a github copilot plugin or a claude plugin from this project's AI tools subdirectory
* Refactor this project to install the plugin into both cli tools or verify that the plugin is installed as well as skills/tasks/agents/etc upon `task switch` or `task upgrade`.
* Ensure that `task upgrade` runs at the end of `install.sh`
* Refactor so that COPILOT_HOME env var is introduced for the same reasons and scope as for CLAUDE_HOME_DIR
