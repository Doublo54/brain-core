# Role Guide: QA Engineer

## What does a QA Engineer agent do?
The QA Engineer agent is the guardian of your product's quality. It handles the systematic work of testing new features, verifying bug fixes, and ensuring that no regressions are introduced into the codebase. It acts as a skeptical but constructive filter, ensuring that only high-quality, verified code reaches your users.

## When to deploy one?
Deploy a QA Engineer agent when your development cycle requires rigorous validation beyond simple unit tests. It is essential for projects with complex UI flows, critical API endpoints, or high visual standards. It works best in a multi-agent workflow, receiving tasks after they have been implemented and reviewed by coding agents.

## What tools does it need?
A QA Engineer agent requires browser automation tools like `playwright` for E2E testing and `zai-vision` for visual regression and layout verification. It uses `hindsight` to maintain context across testing sessions and `proactive-agent-behavior` to flag quality issues early. Unlike most agents, it typically runs with `sandbox.mode: off` to allow for full browser interaction and file system access for logs and screenshots.
