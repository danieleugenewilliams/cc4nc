# Skills

Reusable Claude Code skills referenced in the newsletter. Each directory is a
self-contained skill: a `SKILL.md` plus whatever scripts, templates, and reference
files it bundles.

## Installing a skill

Copy the directory into your user skills folder:

```bash
cp -R skills/build-review-loop ~/.claude/skills/
```

Or into a project, so it loads only inside that repo:

```bash
cp -R skills/build-review-loop <your-repo>/.claude/skills/
```

Claude Code picks it up on the next session. Invoke it by name (`/build-review-loop`)
or just describe the task; the `description` in `SKILL.md` is what Claude matches on.

## Available skills

| Skill | What it does |
|---|---|
| [`build-review-loop`](build-review-loop/) | Sets up a builder–reviewer loop on a repo: two agent sessions that work a backlog through pull requests unattended, with GitHub labels as the state machine. Runs a preflight that can refuse, derives labels from what the repo already has, verifies a test command by running it, then renders the loop's contract and two watch commands from bundled templates. Needs `gh` and `jq`. |
