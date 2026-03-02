# Role Guide: Coding

## What does a coding agent do?
The Coding agent is your primary builder. It handles the heavy lifting of software development, from writing new features to refactoring legacy code and performing rigorous code reviews. It is designed to be concise, opinionated, and focused on shipping high-quality code quickly.

## When to deploy one?
Deploy a Coding agent when you need to scale your development efforts. It's perfect for handling routine tasks, managing PRs, or even leading the development of new modules. It works best when paired with an Orchestrator that can route tasks to it.

## What tools does it need?
A Coding agent requires specialized skills like `coding-orchestrator` and `code-review-orchestrator`. It needs access to your git repositories and typically runs with `sandbox.mode: off` to allow for file system operations and tool execution. It uses `hindsight` to maintain context across long coding sessions.
