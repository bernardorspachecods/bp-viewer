---
bkf: document
description: "Agent rules for this repository: the `scripts/restart-app.sh` step that ends a work round changing app use, and nothing beyond it."
tags: [agents, workflow]
---

[Repository map](/MAP.md)

# Repository-specific instructions

## End of a work round that affects app use 
(doesn’t apply for commits, or documentation changes that dont touch the code)

Do not run this in the middle of a round of changes. Run it only after you have finished working:

```bash
./scripts/restart-app.sh
```

Do not hand off the round until you have confirmed that the script completed the build and opened the app. Explicitly report if the command fails. A failure is not a reason to change another agent's work.
